# Handoff 0057 -- 1:1 link from a ProductSeason to the commerce Product that
# carries its price, orders and licenses. Nullable: a Season stays free/public
# (R3/R4 behaviour) until an admin sets a price, which creates the Product.
class AddProductToProductSeasons < ActiveRecord::Migration[8.1]
  def change
    add_reference :product_seasons, :product, null: true, foreign_key: true, index: { unique: true }
  end
end
