# Handoff 0077 -- a notice (공지) for everyone, guests included. Separate from the service desk on
# purpose (see the migration). The body is Markdown rendered by ContentMarkdown with no parent, so
# it gets the same escaping/sanitizing as episode bodies and can never show an image.
#
# published_at is set the first time a notice is published and kept after that (unpublishing and
# republishing doesn't move it), like an episode's published_at.
class Announcement < ApplicationRecord
  TITLE_MAX = 100

  validates :title, presence: { message: "제목을 입력해 주세요." },
    length: { maximum: TITLE_MAX, message: "제목은 #{TITLE_MAX}자까지 쓸 수 있습니다." }
  validates :body, presence: { message: "본문을 입력해 주세요." }

  normalizes :title, with: ->(title) { title.to_s.strip }

  before_save :stamp_published_at, if: -> { published? && published_at.nil? }
  # At most one pinned notice: pinning one quietly unpins the previous one in the same
  # transaction (0071 featured rule); the partial unique index backs it up.
  before_save :unpin_others, if: -> { pinned? && will_save_change_to_pinned? }

  # Customer list order: the pinned one first, then newest published first.
  scope :listed, -> { where(published: true).order(pinned: :desc, published_at: :desc, id: :desc) }

  # The notice the home announces (R2): published *and* pinned. An unpublished pinned one stays
  # pinned but shows nowhere.
  def self.home_pick
    find_by(published: true, pinned: true)
  end

  def rendered_body
    ContentMarkdown.render(body, profile: :marketing)
  end

  private

  def stamp_published_at
    self.published_at = Time.current
  end

  def unpin_others
    self.class.where(pinned: true).where.not(id: id).update_all(pinned: false, updated_at: Time.current)
  end
end
