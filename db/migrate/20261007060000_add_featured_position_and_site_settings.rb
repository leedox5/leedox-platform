# Handoff 0097 -- the home's featured section holds up to three guides in the operator's order, under a title the
# operator types. `featured` stays the on/off switch (so the home still renders from it before this migration has
# run); `featured_position` (1..3) is the order, unique among featured guides. The guide that is featured now becomes
# number 1, so the home looks the same right after deploy. The title lives in a tiny key/value table (no settings
# store existed).
class AddFeaturedPositionAndSiteSettings < ActiveRecord::Migration[8.1]
  def up
    add_column :product_lines, :featured_position, :integer
    execute "UPDATE product_lines SET featured_position = 1 WHERE featured = #{connection.quoted_true}"
    remove_index :product_lines, name: "index_product_lines_on_featured_only_one"
    add_index :product_lines, :featured_position, unique: true, where: "featured_position IS NOT NULL",
      name: "index_product_lines_on_featured_position"

    create_table :site_settings do |t|
      t.string :key, null: false
      t.string :value
      t.timestamps
    end
    add_index :site_settings, :key, unique: true
  end

  # Back to "at most one featured": only number 1 (or the lowest) stays featured. The title is dropped.
  def down
    drop_table :site_settings
    keep = select_value("SELECT id FROM product_lines WHERE featured = #{connection.quoted_true} ORDER BY featured_position, id LIMIT 1")
    execute "UPDATE product_lines SET featured = #{connection.quoted_false} WHERE featured = #{connection.quoted_true} AND id <> #{keep.to_i}"
    remove_index :product_lines, name: "index_product_lines_on_featured_position"
    remove_column :product_lines, :featured_position
    add_index :product_lines, :featured, unique: true, where: "featured", name: "index_product_lines_on_featured_only_one"
  end
end
