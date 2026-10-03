# Handoff 0073 -- one row per (episode, viewer, KST day). view_count is how many times that
# viewer opened it that day (R3: every open counts); the number of distinct viewer_keys is the
# number of people. viewer_key is an HMAC, never an IP/User-Agent or a raw user id (see
# EpisodeViewTracking). Edited in place for R3 -- never run in production before.
class CreateEpisodeViews < ActiveRecord::Migration[8.1]
  def change
    create_table :episode_views do |t|
      t.references :content_episode, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.date :viewed_on, null: false
      t.string :viewer_key, null: false
      t.integer :view_count, null: false, default: 1
      t.datetime :created_at, null: false
    end
    add_index :episode_views, %i[content_episode_id viewed_on viewer_key], unique: true, name: "index_episode_views_uniqueness"
    add_index :episode_views, :viewed_on
  end
end
