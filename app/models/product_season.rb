# A versioned content edition of a ProductLine (S01, S02, ...) -- handoff
# 0056 R3. Episodes belong to it directly (ContentEpisode#product_season),
# no ContentBundle in between.
#
# `status` gates whether the Season exists for customers at all; `visibility`
# only decides discoverability once published: public = listed on the product
# page and reachable by URL, unlisted = reachable by URL but not listed,
# private = admin-only. Neither carries purchase/License meaning -- that is
# a later commerce round.
class ProductSeason < ApplicationRecord
  SLUG_FORMAT = /\A[a-z0-9]+(-[a-z0-9]+)*\z/
  SEASON_CODE_FORMAT = /\A[A-Z0-9]+\z/
  STATUSES = %w[draft in_review published unpublished archived].freeze
  VISIBILITIES = %w[public unlisted private].freeze

  belongs_to :product_line
  # Handoff 0057 -- the commerce Product carrying this Season's price, orders
  # and licenses (1:1, unique index). Empty = the Season is free/public.
  belongs_to :product, optional: true
  has_many :content_episodes, dependent: :restrict_with_error

  before_validation :normalize_fields

  validates :internal_name, presence: true
  validates :season_code, presence: true, format: { with: SEASON_CODE_FORMAT }, uniqueness: { scope: :product_line_id }
  validates :slug, presence: true, format: { with: SLUG_FORMAT }, uniqueness: { scope: :product_line_id }
  validates :status, inclusion: { in: STATUSES }
  validates :visibility, inclusion: { in: VISIBILITIES }

  scope :ordered, -> { order(:position, :season_code) }
  scope :published, -> { where(status: "published") }
  scope :customer_listed, -> { published.where(visibility: "public") }
  scope :customer_reachable, -> { published.where(visibility: %w[public unlisted]) }

  def published?
    status == "published"
  end

  def customer_reachable?
    published? && %w[public unlisted].include?(visibility)
  end

  # A Season with a commerce Product is license-gated content: its episodes and
  # files require an active license for that Product (see ProductSeasonGates).
  # The license comes from a purchase, or -- for a 0-won Season -- from an
  # explicit free start (Commerce::ClaimFreeSeason). No Product = free/public.
  def gated?
    product_id.present?
  end

  def lifetime_offer
    product&.product_offers&.lifetime&.order(:version)&.last
  end

  def price
    lifetime_offer&.total_amount
  end

  # 0-won Season: shown as free, obtained without an order or payment.
  def free?
    price&.zero? || false
  end

  # A paying customer can order it right now (price > 0, sales on, global
  # commerce switch on). Free Seasons are never orderable -- see #free_start_open?.
  def for_sale?
    gated? && !free? && !!lifetime_offer&.available_at? && Commerce::Sales.enabled_for?(product)
  end

  # A visitor can start a free Season right now. Needs the same explicit
  # "sale started" admin action as a paid one, but no payment provider, so the
  # global commerce switch (a payment safeguard) does not apply.
  def free_start_open?
    gated? && free? && !!lifetime_offer&.available_at? && product.active? && product.sale_enabled? &&
      customer_reachable? && product_line.published?
  end

  # Can a visitor who doesn't own it get it now (buy or free start)?
  def acquirable?
    free? ? free_start_open? : for_sale?
  end

  def display_title
    customer_title.presence || internal_name
  end

  private

  def normalize_fields
    self.season_code = season_code.to_s.strip.upcase.presence
    self.slug = slug.to_s.strip.downcase.presence
  end
end
