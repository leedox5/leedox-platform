# An image placed inside a ProductLine introduction or a ContentEpisode body
# (handoff 0063). A text refers to it as `![alt](image:<public_id>)`; the
# renderer (ContentMarkdown) resolves that only against the images of the very
# record being rendered, so an image can never be pulled into another product's
# or episode's text, and no external image URL is ever rendered.
#
# Like the cover image, the uploaded original is only a source: it is validated
# on upload (ImageUploadValidation) and then served exclusively as the
# re-encoded `body` / `thumb` variants, so a browser never receives the uploaded
# bytes. Unlike the cover, the variants keep the aspect ratio (`resize_to_limit`,
# no crop) -- a screenshot or diagram must not be cut.
class ContentImage < ApplicationRecord
  MAX_FILE_BYTES = 5.megabytes
  MAX_PIXELS = 4096 * 4096
  # Per ProductLine / per Episode. 20 images and 25MB of originals is far more
  # than an introduction or one episode needs, yet bounds what a single record
  # can pile up in the bucket.
  MAX_IMAGES_PER_PARENT = 20
  MAX_TOTAL_BYTES_PER_PARENT = 25.megabytes
  ALT_MAX_LENGTH = 200
  VARIANTS = %w[body thumb].freeze

  belongs_to :product_line, optional: true
  belongs_to :content_episode, optional: true

  has_one_attached :file do |attachable|
    attachable.variant :body, resize_to_limit: [ 1600, nil ], format: :webp, saver: { quality: 82, strip: true }
    attachable.variant :thumb, resize_to_limit: [ 480, nil ], format: :webp, saver: { quality: 80, strip: true }
  end
  include UploadsBeforeCommit
  include ImageUploadValidation

  before_validation :assign_public_id, on: :create
  before_validation :assign_position, on: :create

  validates :alt, presence: { message: "이미지에는 대체문구가 필요합니다" }, length: { maximum: ALT_MAX_LENGTH }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :exactly_one_parent
  validate :file_present
  validate :file_acceptable, if: :new_file_attached?
  validate :storage_accepts_upload, if: :new_file_attached?
  validate :within_parent_limits, on: :create

  scope :ordered, -> { order(:position, :id) }

  def self.max_file_bytes
    MAX_FILE_BYTES
  end

  def self.max_pixels
    MAX_PIXELS
  end

  def self.max_images_per_parent
    MAX_IMAGES_PER_PARENT
  end

  def self.max_total_bytes_per_parent
    MAX_TOTAL_BYTES_PER_PARENT
  end

  # Looked up by the random reference, never by the row id.
  def to_param
    public_id
  end

  def parent
    product_line || content_episode
  end

  # The text this image is referenced from, for the admin "in use" flag.
  def reference
    "image:#{public_id}"
  end

  def markdown_snippet
    "![#{alt}](#{reference})"
  end

  # Whether any text of the parent still names this image.
  def referenced?
    texts = if product_line
      [ product_line.introduction ]
    else
      [ content_episode.body ] + content_episode.content_takeaways.pluck(:body)
    end
    texts.compact.any? { |text| text.include?(reference) }
  end

  # Whether `user` may see the image on a customer page. It follows exactly the
  # gates of the page that shows it, so a picture is never reachable when its
  # text is not: an introduction image needs a reachable (published, not
  # private) product; an episode image needs that plus a published episode and
  # -- for a license-gated product -- an active license. Admins see everything
  # (draft previews).
  def visible_to?(user)
    return true if user&.admin?
    return product_line.customer_reachable? if product_line

    episode = content_episode
    return false unless episode.published?

    case (container = episode.parent)
    when ProductLine
      return false unless container.customer_reachable?
      return true unless container.gated?

      Entitlements::ProductAccess.allowed?(user: user, product_code: container.product.code)
    when ContentBundle
      container.status == "published" && container.product.present? &&
        Entitlements::ProductAccess.allowed?(user: user, product_code: container.product.code)
    else
      false
    end
  end

  # An introduction image is marketing (any visitor of a published product), so a
  # short browser cache is fine; an episode image may be license-gated, so every
  # request goes back through the check.
  def cache_mode
    product_line ? :short : :revalidate
  end

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def assign_position
    return if position.to_i.positive? || parent.nil?

    self.position = (siblings.maximum(:position) || -1) + 1
  end

  def siblings
    product_line ? product_line.content_images : content_episode.content_images
  end

  def exactly_one_parent
    return if product_line.present? ^ content_episode.present?

    errors.add(:base, "이미지는 제품 소개 또는 편 중 정확히 하나에 속해야 합니다.")
  end

  def file_present
    errors.add(:file, "이미지 파일을 첨부해야 합니다.") unless file.attached?
  end

  def new_file_attached?
    new_image_attached?(:file)
  end

  def file_acceptable
    validate_uploaded_image(:file, max_bytes: self.class.max_file_bytes, max_pixels: self.class.max_pixels)
  end

  def storage_accepts_upload
    errors.add(:file, StoragePersistence::MESSAGE) if StoragePersistence.upload_blocked?
  end

  # Counts the stored siblings; the file being added is checked against the
  # remaining room.
  def within_parent_limits
    return if parent.nil?

    if siblings.count >= self.class.max_images_per_parent
      return errors.add(:base, "이미지는 최대 #{self.class.max_images_per_parent}장까지 올릴 수 있습니다.")
    end

    return unless file.attached? && file.blob

    used = siblings.joins(file_attachment: :blob).sum("active_storage_blobs.byte_size")
    if used + file.blob.byte_size > self.class.max_total_bytes_per_parent
      errors.add(:base, "이미지 총 용량은 #{ActiveSupport::NumberHelper.number_to_human_size(self.class.max_total_bytes_per_parent)}까지입니다 " \
                        "(지금 #{ActiveSupport::NumberHelper.number_to_human_size(used)} 사용 중).")
    end
  end
end
