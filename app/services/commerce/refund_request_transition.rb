module Commerce
  class RefundRequestTransition
    ACTIONS = {
      "start_review" => [ "reviewing", "refund_review_started" ],
      "approve" => [ "approved", "refund_approved" ],
      "reject" => [ "rejected", "refund_rejected" ],
      "mark_processing" => [ "processing", "refund_processing_started" ],
      # "processing" -> "refunded" goes through Commerce::ConfirmRefund
      # instead (it also has to cancel the order's license atomically), not
      # this generic transition -- mark_failed has no such side effect, so it
      # stays here.
      "mark_failed" => [ "failed", "refund_failed" ]
    }.freeze

    def self.call!(refund_request:, actor:, action:, public_response: nil, internal_note: nil, at: Time.current)
      ApplicationRecord.transaction do
        refund_request.lock!
        raise Pundit::NotAuthorizedError unless actor&.admin?

        previous_status = refund_request.status
        attributes = note_attributes(public_response, internal_note).merge(processed_by: actor)
        target_status, audit_action = ACTIONS[action.to_s]

        if target_status
          attributes.merge!(timestamps_for(target_status, at))
          attributes[:provider_refund_status] = "pending" if target_status == "processing"
          attributes[:provider_refund_status] = "failed" if target_status == "failed"
          refund_request.transition_to!(target_status, attributes)
          Commerce::AuditRecorder.record!(
            actor: actor,
            action: audit_action,
            auditable: refund_request,
            from_state: previous_status,
            to_state: refund_request.status,
            reason_code: refund_request.reason_code,
            at: at
          )
        elsif action.to_s == "update_notes"
          raise ArgumentError, "no note change" if attributes.except(:processed_by).empty?

          refund_request.update!(attributes)
          Commerce::AuditRecorder.record!(
            actor: actor,
            action: "refund_notes_updated",
            auditable: refund_request,
            from_state: previous_status,
            to_state: previous_status,
            reason_code: refund_request.reason_code,
            at: at
          )
        else
          raise ArgumentError, "unsupported refund action"
        end
        refund_request
      end
    end

    def self.note_attributes(public_response, internal_note)
      {}.tap do |attributes|
        attributes[:public_response] = public_response if public_response.present?
        attributes[:internal_note] = internal_note if internal_note.present?
      end
    end
    private_class_method :note_attributes

    def self.timestamps_for(status, at)
      case status
      when "reviewing" then { reviewed_at: at }
      when "approved", "rejected" then { decided_at: at }
      when "processing" then { processing_started_at: at }
      else {}
      end
    end
    private_class_method :timestamps_for
  end
end
