class CreateContentRevisions < ActiveRecord::Migration[8.1]
  def change
    create_table :content_revisions do |t|
      t.references :episode, null: false, foreign_key: { to_table: :content_episodes }
      t.references :editor, null: true, foreign_key: { to_table: :users }
      t.text :body_snapshot
      t.text :note

      t.timestamps
    end
  end
end
