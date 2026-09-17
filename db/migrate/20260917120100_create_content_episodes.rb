class CreateContentEpisodes < ActiveRecord::Migration[8.1]
  def change
    create_table :content_episodes do |t|
      t.references :bundle, null: false, foreign_key: { to_table: :content_bundles }
      t.references :author, null: true, foreign_key: { to_table: :users }
      t.string :internal_ref
      t.string :customer_title
      t.integer :position, null: false, default: 0
      t.string :evidence_status
      t.text :evidence_note
      t.string :status, null: false, default: "draft"
      t.text :body
      t.datetime :published_at

      t.timestamps
    end

    add_index :content_episodes, %i[bundle_id position]
  end
end
