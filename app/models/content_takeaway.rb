class ContentTakeaway < ApplicationRecord
  belongs_to :episode, class_name: "ContentEpisode", foreign_key: :episode_id, inverse_of: :content_takeaways

  validates :kind, presence: true

  scope :ordered, -> { order(:position) }
end
