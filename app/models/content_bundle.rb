# Content bundle for the R2 vertical slice (handoff 0053) -- a customer-facing
# grouping of episodes that is authored and published from the DB instead of
# HQ markdown. See docs/internal/content_platform_design.md's ProductContent
# interface: ProductContent::DatabaseSource reads bundles/episodes through
# this model instead of scanning hq/<product_code>/.
#
# `slug` (handoff 0055) gives each bundle its own customer URL segment and,
# more importantly, its own episode-numbering scope --
# /content/:product_code/:bundle_slug/:episode_id -- so two bundles under the
# same product can both have an episode "01" without colliding (see
# result.md §2 for the collision this replaces).
class ContentBundle < ApplicationRecord
  # Lowercase kebab-case only, matching the examples in the request
  # ("password-reset-end-to-end", "codex-todo") -- no leading/trailing/
  # doubled hyphens.
  SLUG_FORMAT = /\A[a-z0-9]+(-[a-z0-9]+)*\z/

  belongs_to :product, optional: true
  belongs_to :owner, class_name: "User", optional: true
  has_many :content_episodes, foreign_key: :bundle_id, inverse_of: :bundle, dependent: :destroy

  before_validation :normalize_slug

  validates :internal_name, presence: true
  validates :visibility, inclusion: { in: %w[public unlisted private] }
  validates :status, inclusion: { in: %w[draft in_review published unpublished archived] }
  validates :slug, format: { with: SLUG_FORMAT }, uniqueness: { scope: :product_id }, allow_nil: true
  # A slug is only required once the bundle is actually reachable through a
  # Product's customer URL -- a draft bundle with no Product yet can stay
  # slug-less indefinitely (request §4.1).
  validates :slug, presence: { message: "고객 URL에 쓸 slug가 필요합니다 (Product에 연결된 묶음은 slug가 있어야 합니다)" }, if: :product_id?

  scope :published, -> { where(status: "published") }

  private

  # Blank input normalizes to nil (not ""), so the uniqueness/presence
  # validations above don't collide with other slug-less bundles -- Postgres
  # unique indexes already treat multiple NULLs as distinct, but only if the
  # column actually holds NULL rather than an empty string.
  def normalize_slug
    self.slug = slug.to_s.strip.downcase.presence
  end
end
