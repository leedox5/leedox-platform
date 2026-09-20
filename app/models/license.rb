class License < ApplicationRecord
  SOURCES = %w[paid coupon legacy free].freeze
  STATUSES = %w[scheduled active canceled].freeze
  KST = ActiveSupport::TimeZone["Asia/Seoul"]

  belongs_to :user
  belongs_to :product
  belongs_to :order_item, optional: true

  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }
  validates :starts_on, presence: true
  validates :access_ends_at, :last_usable_on, presence: true, unless: :indefinite?
  validate :period_is_all_or_none
  validate :indefinite_only_for_season_products
  validates :order_item_id, uniqueness: true, allow_nil: true
  validate :period_is_ordered

  scope :for_product, ->(code) { joins(:product).where(products: { code: code }) }
  scope :not_canceled, -> { where.not(status: "canceled") }

  # Handoff 0057 -- NULL access_ends_at (the policy's "expires_at") means the
  # license never expires. It is deliberately not a far-future date: every
  # "is this still valid" question goes through active_at?/effective_status
  # below, so there is no date for a report or a stacking calculation to trip
  # over. Only one-time Season purchases create these; term products never do.
  def indefinite?
    access_ends_at.nil?
  end

  def expires_at
    access_ends_at
  end

  def active_at?(time = Time.current)
    return false if status == "canceled"

    time >= starts_at && (indefinite? || time < access_ends_at)
  end

  def effective_status(at: Time.current)
    return "canceled" if status == "canceled"
    return "scheduled" if at < starts_at
    return "active" if indefinite? || at < access_ends_at

    "expired"
  end

  def starts_at
    KST.local(starts_on.year, starts_on.month, starts_on.day)
  end

  private

  # A missing end date on a term product's license is a bug, not "forever" --
  # only a Season's one-time purchase may create an indefinite license.
  def indefinite_only_for_season_products
    return unless indefinite? && product

    errors.add(:access_ends_at, :blank) unless product.season_product?
  end

  def period_is_all_or_none
    return if access_ends_at.nil? == last_usable_on.nil?

    errors.add(:base, "access_ends_at and last_usable_on must both be set or both be empty (indefinite)")
  end

  def period_is_ordered
    return if starts_on.blank? || last_usable_on.blank? || access_ends_at.blank?

    errors.add(:last_usable_on, "must not be before the start date") if last_usable_on < starts_on
    expected_end = KST.local(
      (last_usable_on + 1.day).year,
      (last_usable_on + 1.day).month,
      (last_usable_on + 1.day).day
    )
    errors.add(:access_ends_at, "must be the next KST midnight") unless access_ends_at == expected_end
  end
end
