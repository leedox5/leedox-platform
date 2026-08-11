class BillingController < ApplicationController
  before_action :authenticate_user!, except: :checkout

  def checkout
    @product_code = params[:product_code].presence || "chatdox"
    @product = Product.find_by(code: @product_code)
    unless Commerce::Sales.enabled_for?(@product)
      @product_landing_path = product_landing_path_for(@product)
      render :checkout
      return
    end

    authenticate_user!
    return if performed?

    @offers = @product.product_offers.active.ordered.select(&:available_at?)
    @existing_license = current_user.licenses
      .where(product: @product)
      .not_canceled
      .where("access_ends_at > ?", Time.current)
      .order(last_usable_on: :desc)
      .first
    kst_today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    @minimum_start_on = kst_today
    @maximum_start_on = kst_today + 7.days

    if @existing_license
      @extension_start_on = @existing_license.last_usable_on + 1.day
      # Mirrors Commerce::OrderCreator's own 12-month cap (handoff 0043) so the
      # checkout page never shows a purchasable form for a start date the
      # server would reject anyway -- this is the proactive UI half of that
      # guard, not a replacement for it.
      @license_stacking_capped = @extension_start_on > (kst_today + 12.months)
    end

    render :checkout_enabled
  end

  def success
    order = find_purchase_order
    unless order
      log_callback_failure(order: nil, provider: nil, status: "order_not_found")
      respond_to_order_not_found
      return
    end

    process_purchase_order_success(order)
  rescue ActiveRecord::ActiveRecordError
    log_callback_failure(order: order, provider: order&.provider, status: "persistence_failed")
    respond_to_payment_reconciliation_failure
  rescue StandardError
    log_callback_failure(order: order, provider: order&.provider, status: "verification_failed")
    respond_to_payment_failure(order)
  end

  def cancel
    product_code = params[:product_code].presence || params[:product].presence
    target_path = product_code.present? ? billing_checkout_path_for(product_code) : pricing_path
    flash[:alert] ||= "결제가 취소되었습니다. 선택한 상품 결제 화면에서 다시 시도하실 수 있습니다."
    flash.keep(:alert)
    redirect_to target_path
  end

  private

  # Every product's own landing page renders the same shared/_product_pricing
  # partial with a #pricing anchor -- this button always means "show me
  # pricing for this product," so it always lands there. A product with no
  # landing_page_path yet (no dedicated marketing page) falls back to root
  # rather than guessing at a URL that doesn't exist.
  def product_landing_path_for(product)
    path = product&.landing_page_path
    return root_path if path.blank?

    "#{path}#pricing"
  end

  def process_purchase_order_success(order)
    raise Pundit::NotAuthorizedError unless order.user == current_user

    gateway = Payments::Gateway.for(order.provider)
    payment_attributes = complete_portone_payment(
      gateway,
      expected_amount: order.total_amount,
      expected_currency: order.currency
    )

    Commerce::OrderFinalizer.call!(order: order, payment: payment_attributes)
    respond_to_payment_success(order)
  end

  def find_purchase_order
    public_id = params[:orderId].presence || params[:paymentId].presence
    Order.find_by(public_id: public_id) if public_id
  end

  def complete_portone_payment(
    gateway,
    expected_amount:,
    expected_currency:
  )
    payment_id = params[:paymentId].presence || params[:orderId]
    payment = gateway.verify_payment!(
      payment_id: payment_id,
      expected_amount: expected_amount,
      expected_currency: expected_currency
    )

    {
      provider: "portone",
      provider_payment_id: payment["id"] || payment["paymentId"] || payment_id,
      order_id: payment_id,
      amount: payment.dig("amount", "total"),
      currency: payment.fetch("currency", expected_currency),
      provider_payload: Payments::ProviderSnapshot.build(provider: "portone", payload: payment)
    }
  end

  def respond_to_payment_success(order)
    product = order&.order_items&.first&.product
    product_name = product&.name || "상품"
    message = "#{product_name} 결제가 완료되었습니다. 대시보드에서 구매한 콘텐츠를 바로 이용하실 수 있습니다."

    if json_payment_request?
      render json: { ok: true, redirectUrl: dashboard_path, message: message }, status: :ok
    else
      redirect_to dashboard_path, notice: message
    end
  end

  def respond_to_payment_failure(order = nil)
    product_code = order&.order_items&.first&.product_code || params[:product_code]
    message = "결제 승인에 실패했습니다. 선택한 상품 결제 화면에서 다시 시도해 주세요."
    cancel_path = product_code.present? ? billing_cancel_path(product_code: product_code) : billing_cancel_path

    if json_payment_request?
      render json: { ok: false, message: message, redirectUrl: cancel_path }, status: :unprocessable_entity
    else
      redirect_to cancel_path, alert: message
    end
  end

  def respond_to_order_not_found
    message = "주문을 확인할 수 없습니다. 상품 페이지에서 다시 시작해 주세요."

    if json_payment_request?
      render json: { ok: false, message: message }, status: :unprocessable_entity
    else
      redirect_to billing_checkout_path, alert: message
    end
  end

  def respond_to_payment_reconciliation_failure
    message = "결제는 확인됐지만 라이선스 반영에 실패했습니다. 재결제하지 마시고 고객센터(#{CompanyInfo::EMAIL})로 문의해 주세요."

    if json_payment_request?
      render json: { ok: false, message: message, redirectUrl: dashboard_path }, status: :internal_server_error
    else
      redirect_to dashboard_path, alert: message
    end
  end

  def json_payment_request?
    request.post? && request.media_type == "application/json"
  end

  def log_callback_failure(order:, provider:, status:)
    Commerce::EventLogger.log(
      event: "commerce.callback_processing_failed",
      provider: order&.provider || provider,
      order: order,
      status: status
    )
  end
end
