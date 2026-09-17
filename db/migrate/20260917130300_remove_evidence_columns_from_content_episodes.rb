# Corrective migration (handoff 0053 R3 §6) -- R2's create_content_episodes
# migration (20260917120100) added evidence_status/evidence_note even though
# the approved R2 scope explicitly said not to: the prototypes' evidence
# labels are per-claim, not per-episode (see result.md §8), so a single
# episode-level enum doesn't fit. The original R2 migration file is left
# untouched (already shared/run in development) -- this removes the columns
# forward instead of rewriting migration history.
class RemoveEvidenceColumnsFromContentEpisodes < ActiveRecord::Migration[8.1]
  def change
    remove_column :content_episodes, :evidence_status, :string
    remove_column :content_episodes, :evidence_note, :text
  end
end
