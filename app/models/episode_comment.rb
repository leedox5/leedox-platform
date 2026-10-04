# Handoff 0074 -- a comment under a customer episode page, or a reply to one (one level only:
# a reply's parent must itself be a top-level comment of the same episode).
#
# Visibility for customers (#visible?): not deleted by its author, not hidden by an admin (R2).
# A top-level comment that isn't visible still shows as a placeholder while it has a visible
# reply, so the replies keep their context; otherwise it's simply left out.
class EpisodeComment < ApplicationRecord
  MAX_LENGTH = 1000
  # Flood control: at most this many comments/replies per user per window. Counted from this
  # table, not Rails.cache -- production's cache store can't be relied on (see result.md).
  RATE_LIMIT = 5
  RATE_WINDOW = 1.minute

  belongs_to :content_episode
  belongs_to :user, optional: true # nil once the account is deleted
  belongs_to :parent, class_name: "EpisodeComment", optional: true
  has_many :replies, class_name: "EpisodeComment", foreign_key: :parent_id, inverse_of: :parent, dependent: :destroy

  normalizes :body, with: ->(body) { body.to_s.strip }

  validates :body, presence: { message: "내용을 입력해 주세요." },
    length: { maximum: MAX_LENGTH, message: "#{MAX_LENGTH}자까지 쓸 수 있습니다." }
  validate :parent_is_top_level_comment_of_same_episode, if: :parent_id?

  scope :top_level, -> { where(parent_id: nil) }

  def self.rate_limited?(user, now: Time.current)
    where(user: user).where(created_at: (now - RATE_WINDOW)..).count >= RATE_LIMIT
  end

  def reply? = parent_id.present?
  def deleted? = deleted_at.present?
  def hidden? = hidden_at.present?
  def visible? = !deleted? && !hidden?

  def authored_by?(viewer)
    viewer.present? && user_id == viewer.id
  end

  # Self-delete: always soft (deleted_at), so a reply-bearing comment can stay as a placeholder
  # and the admin list (R2) can still show it as 삭제됨.
  def soft_delete!
    update_columns(deleted_at: Time.current, updated_at: Time.current)
  end

  private

  # One level only (a reply to a reply is refused here, not just by hiding the button), and only
  # under a comment that's still visible (a deleted/hidden one is just a placeholder).
  def parent_is_top_level_comment_of_same_episode
    if parent.nil? || parent.content_episode_id != content_episode_id
      errors.add(:base, "답글을 달 댓글을 찾을 수 없습니다.")
    elsif parent.reply?
      errors.add(:base, "답글에는 답글을 달 수 없습니다.")
    elsif !parent.visible?
      errors.add(:base, "삭제되었거나 숨겨진 댓글에는 답글을 달 수 없습니다.")
    end
  end
end
