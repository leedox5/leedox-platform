class AddLockVersionToContentEpisodes < ActiveRecord::Migration[8.1]
  def change
    add_column :content_episodes, :lock_version, :integer, null: false, default: 0
  end
end
