class OrderItem < ApplicationRecord
  SNAPSHOT_FIELDS = %w[
    order_id product_id product_offer_id product_code product_name offer_code
    offer_version duration_months supply_amount vat_amount total_amount
    discount_bps currency
  ].freeze

  belongs_to :order
  belongs_to :product
  belongs_to :product_offer
  has_one :license, dependent: :restrict_with_error

  validates :product_code, :product_name, :offer_code, :currency, presence: true
  validates :offer_version, numericality: { only_integer: true, greater_than: 0 }
  validates :duration_months, numericality: { only_integer: true, greater_than: 0 }, unless: :lifetime?
  validates :supply_amount, :vat_amount, :total_amount,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :discount_bps,
    numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000 }
  validates :product_id, uniqueness: { scope: :order_id }
  validate :amounts_add_up
  validate :snapshot_is_immutable, on: :update

  # One-time (no-duration) purchase of a Season -- the item snapshot's
  # duration_months is empty exactly when the offer's was (handoff 0057).
  def lifetime?
    duration_months.nil?
  end

  private

  def amounts_add_up
    return if supply_amount.blank? || vat_amount.blank? || total_amount.blank?
    return if supply_amount + vat_amount == total_amount

    errors.add(:total_amount, "must equal supply amount plus VAT")
  end

  def snapshot_is_immutable
    changed_snapshot_fields = changes_to_save.keys & SNAPSHOT_FIELDS
    return if changed_snapshot_fields.empty?

    errors.add(:base, "order item snapshot cannot be changed after creation")
  end
end
