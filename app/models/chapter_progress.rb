class ChapterProgress < ApplicationRecord
  belongs_to :user

  validates :chapter_id,
    presence: true,
    uniqueness: { scope: [ :user_id, :product_code ] }
  validates :product_code, presence: true, inclusion: { in: -> { Product.pluck(:code) } }
  validate :chapter_id_in_valid_range

  scope :completed, -> { where.not(completed_at: nil) }

  def completed?
    completed_at.present?
  end

  private

  # Chatdox and Claudox chapters are both numbered 1..20, but neither has a
  # shared constant listing valid ids (Curriculum::CHAPTERS is Chatdox-only;
  # Claudox's list is built by scanning the filesystem in ClaudoxController).
  # A simple numeric range check avoids coupling this model to either product's
  # chapter source.
  def chapter_id_in_valid_range
    return if chapter_id.blank?

    errors.add(:chapter_id, :inclusion) unless (1..20).cover?(chapter_id.to_i)
  end
end
