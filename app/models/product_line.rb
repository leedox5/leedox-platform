# Long-lived product identity (problem / result / audience) -- handoff 0056 R3.
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
  COVER_TYPES = {
    ".jpg" => %w[image/jpeg],
    ".jpeg" => %w[image/jpeg],
    ".png" => %w[image/png],
    ".webp" => %w[image/webp]
  }.freeze
  # Purpose-specific sizes, both 16:9. `crop: :attention` (libvips smartcrop)
  # keeps the most salient region if an upload isn't already 16:9, so
  # important content isn't blindly center-cropped.
  COVER_VARIANTS = %w[hero thumb].freeze

  has_many :product_seasons, dependent: :restrict_with_error
  has_one_attached :cover_image do |attachable|
    attachable.variant :hero, resize_to_fill: [ 1600, 900, { crop: :attention } ], format: :webp, saver: { quality: 82, strip: true }
    attachable.variant :thumb, resize_to_fill: [ 480, 270, { crop: :attention } ], format: :webp, saver: { quality: 80, strip: true }
  end
  include UploadsBeforeCommit

  before_validation :normalize_slug

  validates :internal_name, :customer_name, :problem, :expected_result, :target_audience, presence: true
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
    attachment_changes["cover_image"].present?
  end

  # Extension and detected content type must agree, then the bytes are actually
  # decoded: header size against the pixel cap first (cheap, before any pixel
  # is decoded), then a full decode to catch truncated/corrupt files, and
  # animated files are refused (variants are single-frame stills).
  def cover_image_acceptable
    blob = cover_image.blob
    return if blob.nil?

    extension = File.extname(blob.filename.to_s).downcase
    unless COVER_TYPES.key?(extension)
      return errors.add(:cover_image, "허용되지 않는 형식입니다 (허용: JPEG, PNG, WebP — SVG·GIF 등은 사용할 수 없습니다).")
    end
    unless COVER_TYPES[extension].include?(blob.content_type)
      return errors.add(:cover_image, "파일 내용이 #{extension} 이미지와 맞지 않습니다.")
    end
    if blob.byte_size > self.class.max_cover_bytes
      return errors.add(:cover_image, "파일이 너무 큽니다 (최대 #{ActiveSupport::NumberHelper.number_to_human_size(self.class.max_cover_bytes)}).")
    end

    check_cover_decodes
  end

  def check_cover_decodes
    require "vips"
    data = pending_cover_bytes
    return if data.nil?

    image = Vips::Image.new_from_buffer(data, "", fail_on: :truncated)
    pages = image.get_typeof("n-pages").zero? ? 1 : image.get("n-pages")
    return errors.add(:cover_image, "애니메이션 이미지는 사용할 수 없습니다.") if pages > 1

    if image.width * image.height > self.class.max_cover_pixels
      return errors.add(:cover_image, "해상도가 너무 큽니다 (최대 #{(self.class.max_cover_pixels / 1_000_000.0).round(1)}메가픽셀, 예: 4096×4096).")
    end

    image.avg # forces a full decode; raises on truncated or corrupt data
  rescue Vips::Error
    errors.add(:cover_image, "이미지를 읽을 수 없습니다 (손상되었거나 지원하지 않는 파일입니다).")
  end

  def pending_cover_bytes
    attachable = attachment_changes["cover_image"].attachable
    io = attachable.is_a?(Hash) ? attachable[:io] : attachable
    return nil unless io.respond_to?(:read)

    io.rewind if io.respond_to?(:rewind)
    data = io.read
    io.rewind if io.respond_to?(:rewind)
    data
  end

  def normalize_slug
    self.slug = slug.to_s.strip.downcase.presence
  end
end
