# Append-only snapshot of a ContentEpisode's body right before it changes --
# see ContentEpisode#snapshot_previous_body. No diff/restore UI in R3 (see
# handoff 0053 result.md §6 and R3 request §4) -- this is just the audit
# trail those would read from later.
class ContentRevision < ApplicationRecord
  belongs_to :episode, class_name: "ContentEpisode", foreign_key: :episode_id, inverse_of: :content_revisions
  belongs_to :editor, class_name: "User", optional: true

  scope :recent_first, -> { order(created_at: :desc) }
end
