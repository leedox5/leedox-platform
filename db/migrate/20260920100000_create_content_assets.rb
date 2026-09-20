class CreateContentAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :content_assets do |t|
      t.references :content_episode, null: false, foreign_key: true
      t.string :title, null: false
      t.string :kind, null: false
      t.text :description
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :content_assets, %i[content_episode_id position], unique: true
  end
end
