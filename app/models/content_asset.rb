# A downloadable file attached to one ContentEpisode (handoff 0056 R4) --
# source ZIPs, WARs, spec documents. Belongs to the Episode, never to the
# Season/Product; the Season page's "산출물" list is derived from these rows.
#
# The uploaded file's original name is display-only: Active Storage keys the
# stored object by a random blob key, and downloads go through
# ProductLinesController#asset / Admin::ContentAssetsController#download,
# which re-check access on every request (no blob URL is ever rendered).
#
# Cleanup: destroying the row (directly or via ContentEpisode's
# dependent: :destroy) destroys the attachment, and Active Storage's default
# `dependent: :purge_later` then deletes the blob and its stored file; the
# same happens to the old blob when a new file replaces it. That purge runs
# as a background job (Solid Queue in production).
class ContentAsset < ApplicationRecord
  MAX_FILE_SIZE = 100.megabytes

  # Extension is the primary allowlist; the content type Active Storage
  # detects from the file's own bytes must additionally be one of the types
  # legitimately produced by that extension, so "evil.html" renamed to
  # "evil.zip" is still rejected. Nothing a browser would render or execute
  # (HTML, SVG, XML, JS) and no executables are on this list.
  ALLOWED_TYPES = {
    ".zip" => %w[application/zip],
    ".war" => %w[application/zip application/java-archive application/x-tika-java-web-archive],
    ".md" => %w[text/markdown text/x-markdown text/plain],
    ".txt" => %w[text/plain],
    ".pdf" => %w[application/pdf]
  }.freeze

  belongs_to :content_episode
  has_one_attached :file

  validates :title, :kind, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    uniqueness: { scope: :content_episode_id }
  validate :file_present
  validate :file_allowed, if: :new_file_attached?

  scope :ordered, -> { order(:position) }

  def self.max_file_size
    MAX_FILE_SIZE
  end

  def self.allowed_extensions
    ALLOWED_TYPES.keys
  end

  private

  def new_file_attached?
    attachment_changes["file"].present?
  end

  def file_present
    errors.add(:file, "파일을 첨부해야 합니다.") unless file.attached?
  end

  def file_allowed
    blob = file.blob
    return if blob.nil?

    extension = File.extname(blob.filename.to_s).downcase

    unless ALLOWED_TYPES.key?(extension)
      return errors.add(:file, "허용되지 않는 파일 형식입니다 (허용: #{self.class.allowed_extensions.join(', ')}).")
    end

    unless ALLOWED_TYPES[extension].include?(blob.content_type)
      errors.add(:file, "파일 내용이 #{extension} 형식과 맞지 않습니다.")
    end

    if blob.byte_size > self.class.max_file_size
      errors.add(:file, "파일이 너무 큽니다 (최대 #{ActiveSupport::NumberHelper.number_to_human_size(self.class.max_file_size)}).")
    end
  end
end
