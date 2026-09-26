# Handoff 0071 -- home placement for a ProductLine.
#
# track: which home row the series appears in ("basics" = 개발 기초 시즌, "ai" = AI와 함께
#   만들기); NULL keeps it off the home rows (it still shows on /products).
# featured: the one series shown as the home hero. At most one row may be true: the model
#   clears the previous one in the same transaction when another is turned on, and the
#   partial unique index makes that a database guarantee too (two concurrent saves can't
#   both win -- the second one fails instead of leaving two heroes).
class AddTrackAndFeaturedToProductLines < ActiveRecord::Migration[8.1]
  def change
    add_column :product_lines, :track, :string
    add_column :product_lines, :featured, :boolean, null: false, default: false
    add_index :product_lines, :featured, unique: true, where: "featured", name: "index_product_lines_on_featured_only_one"
  end
end
