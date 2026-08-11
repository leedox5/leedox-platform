class BillingOrdersController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_create_product_sales_enabled, only: :create

  def create
    order = Commerce::CheckoutSubmission.call!(
      user: current_user,
      product_code: order_params.fetch(:product_code),
      offer_code: order_params.fetch(:offer_code),
      requested_start_on: order_params[:requested_start_on],
      provider: checkout_provider
    )

    redirect_to billing_order_path(order.public_id)
  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid,
         Commerce::OrderCreator::Unavailable, ArgumentError => e
    Rails.logger.warn("Commerce order rejected: #{e.class.name}")
    redirect_to billing_checkout_path_for(order_params[:product_code]), alert: "주문 조건을 확인해 주세요."
  end

  def show
    @order = current_user.orders.includes(order_items: %i[product product_offer]).find_by!(public_id: params[:id])
    return unless ensure_order_product_sales_enabled!(@order)

    unless @order.status == "pending"
      redirect_to dashboard_path, notice: "이미 처리된 주문입니다."
      return
    end

    @order_item = @order.order_items.first!
    @period = Commerce::PeriodCalculator.call(
      start_on: @order.requested_start_on,
      duration_months: @order_item.duration_months
    )

    if @order.provider == Order::MANUAL_PROVIDER
      @bank_transfer_account_info = ENV.fetch("BANK_TRANSFER_ACCOUNT_INFO", "")
    else
      @portone_store_id = ENV.fetch("PORTONE_STORE_ID", "")
      @portone_channel_key = ENV.fetch("PORTONE_CHANNEL_KEY", "")
    end
  end

  def retry_preview
    @source_order = current_user.orders.includes(order_items: [ :product, :product_offer ]).find_by!(public_id: params[:id])
    return unless ensure_order_product_sales_enabled!(@source_order)

    @assessment = Commerce::PendingOrderAssessment.call(order: @source_order)
    unless retryable?(@source_order, @assessment)
      redirect_to dashboard_path, alert: "이 주문은 안전하게 재시도할 수 없습니다."
      return
    end

    @source_item = @source_order.order_items.first!
    @current_offer = Commerce::RetryOrder.current_offer(@source_order)
    raise ActiveRecord::RecordNotFound unless @current_offer

    @period = Commerce::LicenseScheduler.preview(
      user: current_user,
      product: @source_item.product,
      duration_months: @current_offer.duration_months,
      requested_start_on: Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    )
  end

  def retry
    source_order = current_user.orders.find_by!(public_id: params[:id])
    return unless ensure_order_product_sales_enabled!(source_order)

    order = Commerce::RetryOrder.call!(
      source_order: source_order,
      user: current_user,
      provider: checkout_provider
    )
    redirect_to billing_order_path(order.public_id), notice: "현재 상품 조건으로 새 주문을 만들었습니다."
  rescue Commerce::RetryOrder::Unavailable, Commerce::OrderCreator::Unavailable => e
    # RetryOrder calls OrderCreator internally (see Commerce::RetryOrder), so
    # OrderCreator's own Unavailable reasons (e.g. the 12-month license-start
    # cap, handoff 0043) can surface here too, not just RetryOrder's -- both
    # mean "this order can't proceed as-is," so both land on the same alert.
    Rails.logger.warn("Commerce retry rejected: #{e.class.name}")
    redirect_to dashboard_path, alert: "결제 재시도 조건을 확인해 주세요."
  end

  private

  def order_params
    params.require(:order).permit(:product_code, :offer_code, :requested_start_on)
  end

  def ensure_create_product_sales_enabled
    product_code = params.dig(:order, :product_code)
    return if Commerce::Sales.enabled_for_code?(product_code)

    redirect_to billing_checkout_path_for(product_code), alert: "신규 결제는 준비 중입니다."
  end

  # show/retry_preview/retry all act on an order the current user already
  # owns (loaded via the ownership-scoped find_by! before this runs, so a
  # foreign or missing order still 404s exactly as before -- this gate never
  # gets a chance to turn that into a misleading "sales disabled" redirect).
  # The order's own snapshot is the source of truth for which product it's
  # for, not any one hardcoded product.
  def ensure_order_product_sales_enabled!(order)
    product_code = order.order_items.first&.product_code
    return true if Commerce::Sales.enabled_for_code?(product_code)

    redirect_to billing_checkout_path_for(product_code), alert: "신규 결제는 준비 중입니다."
    false
  end

  # PortOne when it's fully configured, manual bank transfer otherwise -- this
  # is what lets checkout stay open even while PortOne approval is pending.
  def checkout_provider
    configuration = Payments::Configuration.current
    configuration.checkout_ready? ? configuration.provider : Order::MANUAL_PROVIDER
  end

  def retryable?(order, assessment)
    order.status == "abandoned" || (order.status == "pending" && assessment.safe_to_abandon)
  end
end
