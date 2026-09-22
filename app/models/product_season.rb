# LEGACY (handoff 0065). Before the flattening a Season was the sellable unit
# under a ProductLine; now every Season is a ProductLine of its own and this
# table is kept only until the contract step drops it. The app no longer reads
# it for selling, gating or display -- what is left is the record of where each
# line came from (product_lines.legacy_season_id), which the permanent redirects
# from the old Season URLs (LegacySeasonRedirectsController) and SeasonFlatten
# use, and the model that lets them (and the tests) look a Season up.
class ProductSeason < ApplicationRecord
  SLUG_FORMAT = /\A[a-z0-9]+(-[a-z0-9]+)*\z/
  SEASON_CODE_FORMAT = /\A[A-Z0-9]+\z/
  STATUSES = %w[draft in_review published unpublished archived].freeze
  VISIBILITIES = %w[public unlisted private].freeze

  belongs_to :product_line
  belongs_to :product, optional: true

  before_validation :normalize_fields

  validates :internal_name, presence: true
  validates :season_code, presence: true, format: { with: SEASON_CODE_FORMAT }, uniqueness: { scope: :product_line_id }
  validates :slug, presence: true, format: { with: SLUG_FORMAT }, uniqueness: { scope: :product_line_id }
  validates :status, inclusion: { in: STATUSES }
  validates :visibility, inclusion: { in: VISIBILITIES }

  private

  def normalize_fields
    self.season_code = season_code.to_s.strip.upcase.presence
    self.slug = slug.to_s.strip.downcase.presence
  end
end
