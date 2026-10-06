# Optimistic locking is Rails' built-in mechanism (ActiveRecord::Locking::Optimistic) --
# the `lock_version` column alone is enough; no extra code is needed beyond
# forms/controllers round-tripping it (see Admin::ContentEpisodesController#update).
class ContentEpisode < ApplicationRecord
  # A ProductLine (handoff 0065) or -- for the legacy ContentBundle path -- a
  # bundle, exactly one of them (validation below and the DB check).
  # product_season is only the legacy pointer of episodes that existed before
  # the flattening: it is kept during the transition, ignored by the app, and
  # dropped with the product_seasons table in the contract step.
  belongs_to :bundle, class_name: "ContentBundle", foreign_key: :bundle_id, inverse_of: :content_episodes, optional: true
  belongs_to :product_line, optional: true
  belongs_to :product_season, optional: true
  belongs_to :author, class_name: "User", optional: true
  has_many :content_takeaways, foreign_key: :episode_id, inverse_of: :episode, dependent: :destroy
  has_many :content_revisions, foreign_key: :episode_id, inverse_of: :episode, dependent: :destroy
  has_many :content_assets, dependent: :destroy
  # Handoff 0073 -- view counts go with the episode (the FK also cascades in the DB).
  has_many :episode_views, dependent: :delete_all
  # Handoff 0074 -- comments go with the episode (the FK also cascades in the DB).
  has_many :episode_comments, dependent: :delete_all
  # Inline images for the body and takeaways (handoff 0063).
  has_many :content_images, dependent: :destroy

  # Set by the controller before #update (see Admin::ContentEpisodesController)
  # so #snapshot_previous_body can record who made the change -- not a DB
  # column, just carried for the duration of one save.
  attr_accessor :editor

  validates :status, inclusion: { in: %w[draft in_review published unpublished archived] }
  validate :exactly_one_parent
  validates :position, uniqueness: { scope: :bundle_id }, if: :bundle_id?
  validates :position, uniqueness: { scope: :product_line_id }, if: :product_line_id?

  scope :ordered, -> { order(:position) }
  scope :published, -> { where(status: "published") }
  # Handoff 0070 -- the customer product page's "공개 예정" cards: episodes literally
  # marked draft, not any other not-yet-published status (in_review/unpublished/archived
  # are not "coming soon" -- they're intentionally held back or retired).
  scope :draft, -> { where(status: "draft") }

  # Handoff 0070 -- the "공개 예정" episodes of `scope`: draft, in order, and only those with a
  # title (an untitled draft isn't ready to be named to a visitor). Filtered in Ruby with the
  # same `present?` rule as everywhere else, so a whitespace-only title counts as untitled.
  def self.upcoming(scope = all)
    scope.draft.ordered.select { |episode| episode.customer_title.present? }
  end

  before_update :snapshot_previous_body, if: :body_changed?

  # Handoff 0092 R2 -- an "열린 편": the body is open to anyone the guide is open to, licensed or not (files and
  # comments still need the license). False while the column doesn't exist yet (between deploy and migrate).
  def open_preview_on?
    has_attribute?(:open_preview) && open_preview?
  end

  def published?
    status == "published"
  end

  # Handoff 0055 -- the customer/admin-preview "chapter number" for this
  # episode, scoped to its own bundle (position is only unique within a
  # bundle, never globally -- see ProductContent::DatabaseSource).
  def display_id
    position.to_s.rjust(2, "0")
  end

  # The container this episode was authored in, whichever kind it is.
  def parent
    product_line || bundle
  end

  private

  def exactly_one_parent
    return if bundle.present? ^ product_line.present?

    errors.add(:base, "편은 콘텐츠 묶음 또는 제품 중 정확히 하나에 속해야 합니다.")
  end

  # Runs inside the same transaction as the update itself (see Rails' save
  # callback semantics), so a failed save never leaves an orphaned revision.
  def snapshot_previous_body
    content_revisions.create!(body_snapshot: body_was, editor: editor)
  end
end
