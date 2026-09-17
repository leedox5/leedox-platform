# Optimistic locking is Rails' built-in mechanism (ActiveRecord::Locking::Optimistic) --
# the `lock_version` column alone is enough; no extra code is needed beyond
# forms/controllers round-tripping it (see Admin::ContentEpisodesController#update).
class ContentEpisode < ApplicationRecord
  belongs_to :bundle, class_name: "ContentBundle", foreign_key: :bundle_id, inverse_of: :content_episodes
  belongs_to :author, class_name: "User", optional: true
  has_many :content_takeaways, foreign_key: :episode_id, inverse_of: :episode, dependent: :destroy
  has_many :content_revisions, foreign_key: :episode_id, inverse_of: :episode, dependent: :destroy

  # Set by the controller before #update (see Admin::ContentEpisodesController)
  # so #snapshot_previous_body can record who made the change -- not a DB
  # column, just carried for the duration of one save.
  attr_accessor :editor

  validates :status, inclusion: { in: %w[draft in_review published unpublished archived] }

  scope :ordered, -> { order(:position) }
  scope :published, -> { where(status: "published") }

  before_update :snapshot_previous_body, if: :body_changed?

  def published?
    status == "published"
  end

  private

  # Runs inside the same transaction as the update itself (see Rails' save
  # callback semantics), so a failed save never leaves an orphaned revision.
  def snapshot_previous_body
    content_revisions.create!(body_snapshot: body_was, editor: editor)
  end
end
