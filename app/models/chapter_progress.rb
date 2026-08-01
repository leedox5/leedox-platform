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

  def self.for_chapter(user:, product_code:, chapter_id:, source: ProductContent.for(product_code))
    identity = ProductContent::ChapterIdentity.normalize(product_code:, chapter_id:, source:)
    return none unless identity.supported?

    user.chapter_progresses.where(product_code:, chapter_id: identity.aliases)
  end

  def self.complete!(user:, product_code:, chapter_id:, source: ProductContent.for(product_code), at: Time.current)
    identity = ProductContent::ChapterIdentity.normalize(product_code:, chapter_id:, source:)
    raise ActiveRecord::RecordInvalid, new unless identity.supported?

    transaction do
      rows = user.chapter_progresses.lock.where(product_code:, chapter_id: identity.aliases).to_a
      canonical = rows.find { |row| row.chapter_id == identity.canonical_id }
      canonical ||= user.chapter_progresses.new(product_code:, chapter_id: identity.canonical_id)
      completed_at = (rows.filter_map(&:completed_at) + [ at ]).min
      canonical.completed_at = completed_at
      canonical.save!
      rows.each { |row| row.delete unless row.id == canonical.id }
      canonical
    end
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def self.uncomplete!(user:, product_code:, chapter_id:, source: ProductContent.for(product_code))
    for_chapter(user:, product_code:, chapter_id:, source:).delete_all
  end

  private

  def chapter_id_in_valid_range
    return if chapter_id.blank? || product_code.blank?

    source = ProductContent.for(product_code)
    identity = ProductContent::ChapterIdentity.normalize(product_code:, chapter_id:, source:)
    if product_code == "chatdox"
      errors.add(:chapter_id, :inclusion) unless identity.supported?
      return
    end
    return if source.find(chapter_id).present?
    return if chapter_id.match?(/\A(?:0[1-9]|1\d|20)\z/)

    errors.add(:chapter_id, :inclusion)
  end
end
