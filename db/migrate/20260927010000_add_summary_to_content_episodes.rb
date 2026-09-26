# Handoff 0070 -- a one-line teaser for the customer episode card, the same shape as
# ProductLine#summary (handoff 0068): nullable, no length validation (recommended ~60
# chars is help text only), never auto-filled. Shown on both the published card and the
# "공개 예정" (draft) card.
class AddSummaryToContentEpisodes < ActiveRecord::Migration[8.1]
  def change
    add_column :content_episodes, :summary, :string
  end
end
