# Content bundle for the R2 vertical slice (handoff 0053) -- a customer-facing
# grouping of episodes that is authored and published from the DB instead of
# HQ markdown. See docs/internal/content_platform_design.md's ProductContent
# interface: ProductContent::DatabaseSource reads bundles/episodes through
# this model instead of scanning hq/<product_code>/.
class ContentBundle < ApplicationRecord
  belongs_to :product, optional: true
  belongs_to :owner, class_name: "User", optional: true
  has_many :content_episodes, foreign_key: :bundle_id, inverse_of: :bundle, dependent: :destroy

  validates :internal_name, presence: true
  validates :visibility, inclusion: { in: %w[public unlisted private] }
  validates :status, inclusion: { in: %w[draft in_review published unpublished archived] }
end
