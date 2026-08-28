require "securerandom"

module Commerce
  class RefundRequestSubmission
    class Unavailable < StandardError; end

    def self.call!(user:, order:, reason_code:, customer_note:, at: Time.current)
      ApplicationRecord.transaction do
        order.lock!
        raise Pundit::NotAuthorizedError unless order.user_id == user.id
        raise Unavailable, "only paid orders can be requested" unless order.status == "paid"
        raise Unavailable, "an open request already exists" if order.refund_requests.open.exists?
        # Order itself has no "refunded" status (stays "paid" forever, see
        # app/models/order.rb) -- without this, an already-refunded order
        # still passes both checks above and a second refund request could
        # be filed on top of it (found alongside the mypage display bug that
        # showed "환불 요청" again after completion).
        raise Unavailable, "this order was already refunded" if order.refund_requests.exists?(status: "refunded")

        request = order.refund_requests.create!(
          user: user,
          public_id: SecureRandom.uuid,
          status: "requested",
          reason_code: reason_code,
          customer_note: customer_note,
          requested_amount: order.total_amount,
          full_request: true,
          provider_refund_status: "not_requested"
        )
        Commerce::AuditRecorder.record!(
          actor: user,
          action: "refund_requested",
          auditable: request,
          to_state: request.status,
          reason_code: request.reason_code,
          at: at
        )
        request
      end
    rescue ActiveRecord::RecordNotUnique
      raise Unavailable, "an open request already exists"
    end
  end
end
