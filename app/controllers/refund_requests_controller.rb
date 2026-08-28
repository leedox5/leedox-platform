class RefundRequestsController < ApplicationController
  before_action :authenticate_user!

  def new
    @order = current_user.orders.includes(order_items: :license).find_by!(public_id: params[:id])
    unless @order.status == "paid"
      redirect_to dashboard_path, alert: "결제 완료 주문만 환불 요청을 접수할 수 있습니다."
      return
    end
    if (open_request = @order.refund_requests.open.first)
      redirect_to refund_request_path(open_request.public_id), notice: "이미 접수된 환불 요청이 있습니다."
      return
    end
    if (completed_request = @order.refund_requests.find_by(status: "refunded"))
      redirect_to refund_request_path(completed_request.public_id), notice: "이미 환불이 완료된 주문입니다."
      return
    end

    @refund_request = RefundRequest.new(order: @order, user: current_user, full_request: true)
  end

  def create
    order = current_user.orders.find_by!(public_id: params[:id])
    request_record = Commerce::RefundRequestSubmission.call!(
      user: current_user,
      order: order,
      reason_code: refund_request_params.fetch(:reason_code),
      customer_note: refund_request_params[:customer_note]
    )
    redirect_to refund_request_path(request_record.public_id), notice: "환불 요청이 접수되었습니다."
  rescue Commerce::RefundRequestSubmission::Unavailable, ActiveRecord::RecordInvalid, KeyError
    redirect_to dashboard_path, alert: "환불 요청 조건을 확인해 주세요."
  end

  def show
    @refund_request = current_user.refund_requests.includes(order: { order_items: :license })
      .find_by!(public_id: params[:id])
    @order = @refund_request.order
  end

  private

  def refund_request_params
    params.require(:refund_request).permit(:reason_code, :customer_note)
  end
end
