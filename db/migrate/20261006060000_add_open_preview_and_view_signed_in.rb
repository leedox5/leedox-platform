# Handoff 0092 R2 (D-012) -- "열린 편": an episode whose body anyone can read, licensed or not (the admin switches it
# on per episode -- 로그인 없이 보기 허용). Off for every episode, existing ones included, so deploying changes nothing.
# And whether an episode view was a signed-in member's: set on new rows only; rows written before this have no way
# to tell (their viewer_key is an HMAC), so they stay NULL = unknown rather than a guessed value.
class AddOpenPreviewAndViewSignedIn < ActiveRecord::Migration[8.1]
  def change
    add_column :content_episodes, :open_preview, :boolean, null: false, default: false
    add_column :episode_views, :signed_in, :boolean
  end
end
