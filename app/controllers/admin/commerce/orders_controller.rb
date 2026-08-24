class Admin::Commerce::OrdersController < Admin::BaseController
  helper_method :pending_assessment

  def index
    @orders = filtered_orders.limit(100)
    @reconciliation_issues = Commerce::Reconciliation.call(log: false)
      .issues.group_by(&:order_public_id)
  end

  def show
    @order = order_scope.find_by!(public_id: params[:id])
    @assessment = pending_assessment(@order)
    @issues = Commerce::Reconciliation.call(log: false)
      .issues.select { |issue| issue.order_public_id == @order.public_id }
    @audits = @order.commerce_audit_events.includes(:actor).order(occurred_at: :desc)
    record_stale_classification if @assessment.stale
  end

  def abandon
    order = order_scope.find_by!(public_id: params[:id])
    Commerce::AbandonOrder.call!(order: order, actor: current_user)
    redirect_to admin_commerce_order_path(order.public_id), notice: "결제 이탈 주문으로 정리했습니다."
  rescue Commerce::AbandonOrder::Unsafe => e
    Rails.logger.warn("Commerce abandon rejected: #{e.class.name}")
    redirect_to admin_commerce_order_path(params[:id]), alert: "PG 확인이 필요한 주문은 정리할 수 없습니다."
  end

  def confirm_manual_payment
    order = order_scope.find_by!(public_id: params[:id])
    Commerce::ConfirmManualPayment.call!(order: order, actor: current_user)
    redirect_to admin_commerce_order_path(order.public_id), notice: "입금을 확인하고 라이선스를 발급했습니다."
  rescue Commerce::ConfirmManualPayment::Unavailable => e
    Rails.logger.warn("Commerce manual payment confirmation rejected: #{e.class.name}")
    redirect_to admin_commerce_order_path(params[:id]), alert: "무통장입금 대기 중인 주문만 확인할 수 있습니다."
  rescue ActiveRecord::ActiveRecordError => e
    # OrderFinalizer already logs commerce.order_finalization_failed before
    # re-raising -- this only turns that into a page instead of a 500. Seen
    # in production (2026-08-24): confirming a stale duplicate manual order
    # whose user/product/start-date already had a real license hit the
    # licenses unique index and crashed instead of explaining why.
    Rails.logger.warn("Commerce manual payment confirmation failed to persist: #{e.class.name}")
    redirect_to admin_commerce_order_path(params[:id]), alert: "이 주문을 확인할 수 없습니다 — 같은 사용자·상품·시작일로 이미 라이선스가 존재합니다. 중복 주문인지 확인해 주세요."
  end

  private

  def order_scope
    Order.includes(
      :user,
      :refund_requests,
      :licenses,
      :payment_transaction,
      order_items: [ :product, :product_offer, :license ]
    ).strict_loading
  end

  def filtered_orders
    scope = order_scope.order(created_at: :desc)
    scope = scope.where(status: params[:status]) if Order::STATUSES.include?(params[:status])
    scope = scope.where(provider: params[:provider]) if Payments::Gateway::PROVIDERS.include?(params[:provider])
    scope = scope.joins(:order_items).where(order_items: { product_code: params[:product] }) if params[:product].present?
    scope = apply_date_filter(scope, :from, ">=")
    scope = apply_date_filter(scope, :to, "<=")
    apply_pending_age_filter(scope)
  end

  def apply_date_filter(scope, key, operator)
    return scope if params[key].blank?

    date = Date.iso8601(params[key])
    boundary = key == :to ? date.end_of_day : date.beginning_of_day
    case operator
    when ">=" then scope.where("orders.created_at >= ?", boundary)
    when "<=" then scope.where("orders.created_at <= ?", boundary)
    else scope
    end
  rescue Date::Error
    scope
  end

  def apply_pending_age_filter(scope)
    cutoff = Time.current - Commerce::PendingOrderAssessment.configured_stale_after
    case params[:pending_age]
    when "fresh" then scope.where(status: "pending").where("payment_requested_at >= ?", cutoff)
    when "stale" then scope.where(status: "pending").where("payment_requested_at < ?", cutoff)
    else scope
    end
  end

  def pending_assessment(order)
    Commerce::PendingOrderAssessment.call(order: order)
  end

  def record_stale_classification
    @order.commerce_audit_events.find_or_create_by!(
      actor: current_user,
      action: "stale_order_classified",
      from_state: @order.status,
      to_state: @order.status,
      reason_code: @assessment.reason_code
    ) { |event| event.occurred_at = Time.current }
  end
end
