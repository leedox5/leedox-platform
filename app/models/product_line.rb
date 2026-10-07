# Long-lived product identity -- handoff 0056 R3. Its customer-facing description is
# one free-form `introduction` (handoff 0060; it replaced the fixed problem / result /
# audience fields, whose columns are still in the table but no longer used).
# Since handoff 0065 it is the sellable unit: it owns its episodes directly and
# carries the 1:1 commerce Product (price, orders, licenses). "Same series" is
# only a loose, optional relation (series_key / series_label / series_position).
#
# `cover_image` (handoff 0056 R5) is the product's customer-facing hero image,
# one per product -- a different responsibility from ContentAsset (an
# episode's downloadable file). The uploaded original is only ever a source:
# it is validated on upload and then served exclusively as the re-encoded
# `hero` / `thumb` variants below, so a customer or admin browser never
# receives the uploaded bytes (no metadata, no polyglot content, no
# unbounded pixel size).
class ProductLine < ApplicationRecord
  SLUG_FORMAT = /\A[a-z0-9]+(-[a-z0-9]+)*\z/
  STATUSES = %w[draft published unpublished].freeze
  # Handoff 0065 -- public = reachable (and listable), unlisted = reachable by
  # URL only, private = admin-only. Neither says anything about purchase.
  VISIBILITIES = %w[public unlisted private].freeze
  # Handoff 0071 -- the home row a series appears in; nil keeps it off the home rows.
  TRACKS = { "basics" => "개발 기초 시즌", "ai" => "AI와 함께 만들기" }.freeze
  # Handoff 0091 (D-011) -- the home rows' titles: no 시즌 on customer screens. TRACKS stays the admin's wording
  # (the 홈 줄 select and the list) until the admin screens' words are decided (backlog 0068).
  TRACK_TITLES = { "basics" => "개발 기초", "ai" => "AI와 함께 만들기" }.freeze

  # Recommended upload is 16:9 at 1600x900. 5MB is far above a well-compressed
  # 1600x900 JPEG/WebP (~0.2-0.8MB) and a flat PNG (~1-3MB) while stopping
  # multi-megabyte camera originals from piling up; 4096x4096 (~16.7MP) bounds
  # decode memory (a decoded RGBA frame is ~67MB) well before it can hurt.
  COVER_MAX_BYTES = 5.megabytes
  COVER_MAX_PIXELS = 4096 * 4096
  COVER_ALT_MAX_LENGTH = 200
  # A recommendation shown as help text on the admin form, not a validation (handoff
  # 0068) -- a slightly longer summary is never rejected.
  SUMMARY_RECOMMENDED_MAX = 60
  COVER_TYPES = ImageUploadValidation::TYPES
  # Purpose-specific sizes, both 16:9. `crop: :attention` (libvips smartcrop)
  # keeps the most salient region if an upload isn't already 16:9, so
  # important content isn't blindly center-cropped.
  COVER_VARIANTS = %w[hero thumb].freeze

  # Handoff 0065 -- the ProductLine is the sellable unit: it carries the
  # commerce Product (price, orders, licenses; 1:1) and owns its episodes
  # directly. ProductSeason is gone from the app (its table stays until the
  # contract step).
  belongs_to :product, optional: true
  has_many :content_episodes, dependent: :restrict_with_error
  # Inline images for the introduction (handoff 0063).
  has_many :content_images, dependent: :destroy
  has_one_attached :cover_image do |attachable|
    attachable.variant :hero, resize_to_fill: [ 1600, 900, { crop: :attention } ], format: :webp, saver: { quality: 82, strip: true }
    attachable.variant :thumb, resize_to_fill: [ 480, 270, { crop: :attention } ], format: :webp, saver: { quality: 80, strip: true }
  end
  include UploadsBeforeCommit
  include ImageUploadValidation

  before_validation :normalize_slug
  before_validation :normalize_series
  before_validation { self.track = track.presence }

  validates :internal_name, :customer_name, :introduction, presence: true
  validates :slug, presence: true, format: { with: SLUG_FORMAT }, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :visibility, inclusion: { in: VISIBILITIES }
  # "Same series" is a loose, optional relation between independent products.
  validates :series_key, format: { with: SLUG_FORMAT, message: "은 소문자·숫자·하이픈만 쓸 수 있습니다" }, allow_nil: true
  validates :series_label, length: { maximum: 40 }
  validates :series_position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :track, inclusion: { in: TRACKS.keys }, allow_nil: true

  # Handoff 0097 -- up to FEATURED_MAX featured guides (was one, 0071), in the operator's order (featured_position
  # 1..3, unique -- a partial unique index backs it). Turning one on puts it last; a fourth is refused, never
  # switching another off. Turning one off clears its place. The order is changed from the admin list
  # (ProductLine.arrange_featured!).
  FEATURED_MAX = 3
  before_validation :place_featured
  validates :featured_position, inclusion: { in: 1..FEATURED_MAX }, allow_nil: true, if: -> { has_attribute?(:featured_position) }
  validate :featured_position_free, if: -> { has_attribute?(:featured_position) && featured_position.present? && will_save_change_to_featured_position? }
  validates :cover_image_alt, presence: { message: "대표 이미지를 올리면 대체문구가 필요합니다" }, if: -> { cover_image.attached? }
  validates :cover_image_alt, length: { maximum: COVER_ALT_MAX_LENGTH }
  validate :cover_image_acceptable, if: :new_cover_image?
  validate :storage_accepts_cover_upload, if: :new_cover_image?

  scope :published, -> { where(status: "published") }
  # What a visitor may open: published, and not private (unlisted is reachable by URL).
  scope :customer_reachable, -> { published.where(visibility: %w[public unlisted]) }
  # What belongs on the customer product list (handoff 0068): public only -- unlisted is
  # reachable by URL but deliberately not listed anywhere (see VISIBILITIES above).
  scope :listed, -> { published.where(visibility: "public") }
  scope :in_track, ->(track) { where(track: track) }

  # Handoff 0097 -- the home's featured section: the listed featured guides in the operator's order (at most
  # FEATURED_MAX). Sorted here rather than in SQL, and through `try`, so the home still renders (in id order) during
  # the deploy window before the featured_position column exists.
  def self.home_featured
    listed.where(featured: true).includes(:product, cover_image_attachment: :blob).to_a
      .sort_by { |line| [ line.try(:featured_position) || FEATURED_MAX + 1, line.id ] }
      .first(FEATURED_MAX)
  end

  # Handoff 0097 -- the admin list's 홈 대표 섹션: {id => "1".."3" or "" (take it off the home)} for the guides that
  # are featured now. The numbers must be distinct; returns an error message, or nil once saved. All places are
  # cleared first and then set, so two guides can swap places in one save.
  def self.arrange_featured!(positions)
    lines = where(featured: true, id: positions.keys).to_a
    places = lines.to_h { |line| [ line, positions[line.id.to_s].presence&.to_i ] }
    kept = places.values.compact
    return "대표 순서는 1~#{FEATURED_MAX} 중에서 골라 주세요." unless kept.all? { |n| (1..FEATURED_MAX).cover?(n) }
    return "대표 순서가 겹칩니다. 1~#{FEATURED_MAX}을 하나씩 골라 주세요." unless kept.uniq.size == kept.size

    transaction do
      where(id: lines.map(&:id)).update_all(featured_position: nil, updated_at: Time.current)
      places.each do |line, place|
        line.update_columns(place ? { featured_position: place } : { featured: false, featured_position: nil })
      end
    end
    nil
  end

  def published?
    status == "published"
  end

  def customer_reachable?
    published? && %w[public unlisted].include?(visibility)
  end

  # --- selling (moved here from ProductSeason, handoff 0065) -----------------

  # A line with a commerce Product is license-gated: its episodes and files
  # need an active license for that Product. The license comes from a purchase
  # or, for a 0-won product, from an explicit free start (Commerce::ClaimFreeAccess).
  # No Product = free and public.
  def gated?
    product_id.present?
  end

  def lifetime_offer
    product&.product_offers&.lifetime&.order(:version)&.last
  end

  def price
    lifetime_offer&.total_amount
  end

  # 0-won product: shown as free, obtained without an order or payment.
  def free?
    price&.zero? || false
  end

  # A paying customer can order it right now (price > 0, sales on, global
  # commerce switch on). Free products are never orderable -- see #free_start_open?.
  def for_sale?
    gated? && !free? && !!lifetime_offer&.available_at? && Commerce::Sales.enabled_for?(product)
  end

  # A visitor can start a free product right now. Needs the same explicit
  # "sale started" admin action as a paid one, but no payment provider, so the
  # global commerce switch (a payment safeguard) does not apply.
  def free_start_open?
    gated? && free? && !!lifetime_offer&.available_at? && product.active? && product.sale_enabled? && customer_reachable?
  end

  # Can a visitor who doesn't own it get it now (buy or free start)?
  def acquirable?
    free? ? free_start_open? : for_sale?
  end

  # Whether `user` already has this product -- the same check the purchase box uses to
  # decide "owned" (handoff 0057/0065), pulled out to a model method so the product list
  # (handoff 0068) asks the identical question instead of a second copy of the logic.
  def owned_by?(user)
    gated? && user.present? && Entitlements::ProductAccess.allowed?(user: user, product_code: product.code)
  end

  # The purchase box's state, in the one priority order it already renders in (handoff
  # 0057; owned beats a free product being open, which beats it being for sale) -- shared
  # with the product list (handoff 0068) so the two can never disagree about a product's
  # state. nil for a product with no commerce Product at all (nothing to show).
  def access_state(owned:)
    return nil unless gated?
    return :owned if owned
    return :free_open if free? && free_start_open?
    return :for_sale if !free? && for_sale?

    :unavailable
  end

  # The other products of the same series, in order (empty for a stand-alone product).
  # The episodes a visitor can open, in order (the product page's cards and its gate).
  def published_episodes
    content_episodes.published.ordered
  end

  # Handoff 0070 -- titled draft episodes, shown as non-link "공개 예정" cards. Kept here (not in
  # a controller) so the product page and the home (handoff 0071) use the exact same judgment.
  def upcoming_episodes
    ContentEpisode.upcoming(content_episodes)
  end

  def track_name
    TRACKS[track]
  end

  def series_members
    series_key.present? ? ProductLine.where(series_key: series_key).order(:series_position, :id) : ProductLine.none
  end

  def self.max_cover_bytes
    COVER_MAX_BYTES
  end

  def self.max_cover_pixels
    COVER_MAX_PIXELS
  end

  # Width x height, read from the stored original (analysed synchronously the
  # first time, since Active Storage's own analysis runs as a background job).
  def cover_dimensions
    return nil unless cover_image.attached?

    cover_image.analyze unless cover_image.analyzed?
    width = cover_image.metadata[:width]
    height = cover_image.metadata[:height]
    [ width, height ] if width && height
  end

  private

  def place_featured
    return unless has_attribute?(:featured_position) # the deploy window before the 0097 migration

    unless featured?
      self.featured_position = nil
      return
    end
    return if featured_position.present?

    taken = self.class.where(featured: true).where.not(id: id).where.not(featured_position: nil)
    free = (1..FEATURED_MAX).to_a - taken.pluck(:featured_position)
    if free.empty?
      names = taken.order(:featured_position).pluck(:customer_name).join(", ")
      errors.add(:base, "대표 가이드는 #{FEATURED_MAX}개까지입니다. 지금: #{names}")
      throw :abort
    end
    after_last = (taken.maximum(:featured_position) || 0) + 1
    self.featured_position = after_last <= FEATURED_MAX ? after_last : free.first
  end

  def featured_position_free
    holder = self.class.where(featured_position: featured_position).where.not(id: id).first
    errors.add(:base, "대표 순서 #{featured_position}번은 이미 '#{holder.customer_name}'이(가) 쓰고 있습니다") if holder
  end

  def storage_accepts_cover_upload
    errors.add(:cover_image, StoragePersistence::MESSAGE) if StoragePersistence.upload_blocked?
  end

  def new_cover_image?
    new_image_attached?(:cover_image)
  end

  def cover_image_acceptable
    validate_uploaded_image(:cover_image, max_bytes: self.class.max_cover_bytes, max_pixels: self.class.max_cover_pixels)
  end

  def normalize_slug
    self.slug = slug.to_s.strip.downcase.presence
  end

  def normalize_series
    self.series_key = series_key.to_s.strip.downcase.presence
    self.series_label = series_label.to_s.strip.presence
  end
end
