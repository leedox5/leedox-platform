module Commerce
  # Admin action for the step admin/commerce/refund_requests/show.html.erb has
  # always documented as NOT doing yet ("이 화면에서는 refunded 확정, Order
  # 상태 변경과 License 변경을 수행하지 않습니다") -- an admin who actually
  # canceled the payment on PortOne's side (this app has no PG cancel API
  # integration, see Payments::PortoneGateway) comes back here to record that
  # and revoke the license it paid for, in one atomic step so the two can't
  # drift apart (see Commerce::Reconciliation#refunded_license_policy_unresolved,
  # which already anticipated this exact gap).
  class ConfirmRefund
    class Unavailable < StandardError; end

    def self.call!(refund_request:, actor:, at: Time.current)
      new(refund_request: refund_request, actor: actor, at: at).call!
    end

    def initialize(refund_request:, actor:, at:)
      @refund_request = refund_request
      @actor = actor
      @at = at
    end

    def call!
      raise Pundit::NotAuthorizedError unless @actor&.admin?

      ApplicationRecord.transaction do
        @refund_request.lock!
        raise Unavailable, "refund request is not in processing" unless @refund_request.status == "processing"

        @refund_request.transition_to!(
          "refunded",
          external_refund_confirmed: true,
          provider_refund_status: "confirmed",
          external_processed_at: @at
        )

        @refund_request.order.licenses.not_canceled.find_each do |license|
          license.update!(status: "canceled")
        end

        Commerce::AuditRecorder.record!(
          actor: @actor,
          action: "refund_confirmed",
          auditable: @refund_request,
          from_state: "processing",
          to_state: "refunded",
          reason_code: @refund_request.reason_code,
          at: @at
        )

        @refund_request
      end
    end
  end
end
