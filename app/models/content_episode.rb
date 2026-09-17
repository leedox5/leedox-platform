class ContentEpisode < ApplicationRecord
  belongs_to :bundle, class_name: "ContentBundle", foreign_key: :bundle_id, inverse_of: :content_episodes
  belongs_to :author, class_name: "User", optional: true

  validates :status, inclusion: { in: %w[draft in_review published unpublished archived] }

  scope :ordered, -> { order(:position) }

  def published?
    status == "published"
  end
end
