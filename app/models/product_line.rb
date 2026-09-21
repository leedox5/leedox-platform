# Long-lived product identity -- handoff 0056 R3. Its customer-facing description is
# one free-form `introduction` (handoff 0060; it replaced the fixed problem / result /
# audience fields, whose columns are still in the table but no longer used).
# Owns ProductSeasons; deliberately has no relation to the commerce Product
# yet (that 1:1 link belongs to the later pricing/License round, hung off
# ProductSeason rather than here).
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

  # Recommended upload is 16:9 at 1600x900. 5MB is far above a well-compressed
  # 1600x900 JPEG/WebP (~0.2-0.8MB) and a flat PNG (~1-3MB) while stopping
  # multi-megabyte camera originals from piling up; 4096x4096 (~16.7MP) bounds
  # decode memory (a decoded RGBA frame is ~67MB) well before it can hurt.
  COVER_MAX_BYTES = 5.megabytes
  COVER_MAX_PIXELS = 4096 * 4096
  COVER_ALT_MAX_LENGTH = 200
  COVER_TYPES = ImageUploadValidation::TYPES
  # Purpose-specific sizes, both 16:9. `crop: :attention` (libvips smartcrop)
  # keeps the most salient region if an upload isn't already 16:9, so
  # important content isn't blindly center-cropped.
  COVER_VARIANTS = %w[hero thumb].freeze

  has_many :product_seasons, dependent: :restrict_with_error
  # Inline images for the introduction (handoff 0063).
  has_many :content_images, dependent: :destroy
  has_one_attached :cover_image do |attachable|
    attachable.variant :hero, resize_to_fill: [ 1600, 900, { crop: :attention } ], format: :webp, saver: { quality: 82, strip: true }
    attachable.variant :thumb, resize_to_fill: [ 480, 270, { crop: :attention } ], format: :webp, saver: { quality: 80, strip: true }
  end
  include UploadsBeforeCommit
  include ImageUploadValidation

  before_validation :normalize_slug

  validates :internal_name, :customer_name, :introduction, presence: true
  validates :slug, presence: true, format: { with: SLUG_FORMAT }, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :cover_image_alt, presence: { message: "대표 이미지를 올리면 대체문구가 필요합니다" }, if: -> { cover_image.attached? }
  validates :cover_image_alt, length: { maximum: COVER_ALT_MAX_LENGTH }
  validate :cover_image_acceptable, if: :new_cover_image?
  validate :storage_accepts_cover_upload, if: :new_cover_image?

  scope :published, -> { where(status: "published") }

  def published?
    status == "published"
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
end
