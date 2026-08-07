class CommerceAuditEvent < ApplicationRecord
  ACTIONS = %w[
    stale_order_classified order_abandoned retry_order_created
    refund_requested refund_review_started refund_approved refund_rejected
    refund_processing_started refund_notes_updated late_provider_success_observed
    product_sale_toggled product_pricing_updated manual_payment_confirmed free_license_granted
  ].freeze

  belongs_to :actor, class_name: "User", optional: true
  belongs_to :auditable, polymorphic: true

  validates :action, inclusion: { in: ACTIONS }
  validates :occurred_at, presence: true
  validates :from_state, :to_state, :reason_code, length: { maximum: 100 }, allow_blank: true
end
