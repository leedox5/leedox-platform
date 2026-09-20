class AddProductSeasonToContentEpisodes < ActiveRecord::Migration[8.1]
  def change
    change_column_null :content_episodes, :bundle_id, true
    add_reference :content_episodes, :product_season, null: true, foreign_key: true
    add_index :content_episodes, %i[product_season_id position], unique: true, name: "index_content_episodes_on_season_and_position"
    add_check_constraint :content_episodes,
      "(bundle_id IS NOT NULL AND product_season_id IS NULL) OR (bundle_id IS NULL AND product_season_id IS NOT NULL)",
      name: "content_episodes_exactly_one_parent"
  end
end
