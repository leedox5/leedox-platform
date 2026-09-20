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

  def display_title
    customer_title.presence || internal_name
  end

  private

  def normalize_fields
    self.season_code = season_code.to_s.strip.upcase.presence
    self.slug = slug.to_s.strip.downcase.presence
  end
end
