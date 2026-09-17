class CreateContentTakeaways < ActiveRecord::Migration[8.1]
  def change
    create_table :content_takeaways do |t|
      t.references :episode, null: false, foreign_key: { to_table: :content_episodes }
      t.string :kind, null: false
      t.text :body
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :content_takeaways, %i[episode_id position]
  end
end
