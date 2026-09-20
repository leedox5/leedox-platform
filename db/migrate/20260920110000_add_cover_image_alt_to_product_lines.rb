class AddCoverImageAltToProductLines < ActiveRecord::Migration[8.1]
  def change
    add_column :product_lines, :cover_image_alt, :string
  end
end
