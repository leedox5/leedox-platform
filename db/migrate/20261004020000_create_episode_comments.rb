# Handoff 0074 -- comments (and one level of replies) under a customer episode page.
# Nothing is ever hard-deleted from the app: a self-delete sets deleted_at, an admin hide
# (R2) sets hidden_at, so both can be shown as placeholders while replies remain and the
# admin list can still show what happened. user_id is nullable so a deleted account
# leaves "탈퇴한 사용자" instead of blocking the delete.
class CreateEpisodeComments < ActiveRecord::Migration[8.1]
  def change
    create_table :episode_comments do |t|
      t.references :content_episode, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: true, foreign_key: { on_delete: :nullify }
      t.references :parent, null: true, foreign_key: { to_table: :episode_comments, on_delete: :cascade }
      t.text :body, null: false
      t.datetime :hidden_at
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :episode_comments, %i[content_episode_id created_at]
    add_index :episode_comments, :created_at
  end
end
