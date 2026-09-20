class CreateProductSeasons < ActiveRecord::Migration[8.1]
  def change
    create_table :product_seasons do |t|
      t.references :product_line, null: false, foreign_key: true
      t.string :internal_name, null: false
      t.string :customer_title
      t.string :season_code, null: false
      t.string :slug, null: false
      t.string :status, null: false, default: "draft"
      t.string :visibility, null: false, default: "public"
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :product_seasons, %i[product_line_id season_code], unique: true
    add_index :product_seasons, %i[product_line_id slug], unique: true
  end
end
