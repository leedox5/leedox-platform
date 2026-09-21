# Handoff 0063 -- inline images for a ProductLine introduction or a ContentEpisode
# body. Additive only: nothing existing is altered, so the new code keeps working
# on the old schema until this runs, as long as it does not touch the table (the
# renderer only queries it when a text actually contains an `image:` reference).
class CreateContentImages < ActiveRecord::Migration[8.1]
  def change
    create_table :content_images do |t|
      # Exactly one parent (see the check constraint), the same pattern as
      # content_episodes' bundle/season parent.
      t.references :product_line, foreign_key: true
      t.references :content_episode, foreign_key: true
      # What a text refers to (`![alt](image:<public_id>)`). Random and not
      # derived from the row id, so an image cannot be guessed from its number.
      t.string :public_id, null: false
      t.string :alt, null: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :content_images, :public_id, unique: true
    add_check_constraint :content_images,
      "(product_line_id IS NOT NULL AND content_episode_id IS NULL) OR (product_line_id IS NULL AND content_episode_id IS NOT NULL)",
      name: "content_images_exactly_one_parent"
  end
end
