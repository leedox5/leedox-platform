# Handoff 0078 -- whether a standalone (pre-series) product appears in the home's "AI와 함께 만들기"
# row. Off by default for anything created from now on; every standalone product that exists at
# migration time starts on, so the home looks exactly as before the deploy. A Product that is the
# commerce side of a ProductLine (Product.standalone excludes those) keeps false -- the value means
# nothing for it.
class AddShowOnHomeToProducts < ActiveRecord::Migration[8.1]
  # Every product that isn't the commerce side of a ProductLine (= Product.standalone).
  BACKFILL_SQL = <<~SQL.squish.freeze
    UPDATE products SET show_on_home = TRUE
    WHERE id NOT IN (SELECT product_id FROM product_lines WHERE product_id IS NOT NULL)
  SQL

  def up
    add_column :products, :show_on_home, :boolean, null: false, default: false
    execute BACKFILL_SQL
  end

  def down
    remove_column :products, :show_on_home
  end
end
