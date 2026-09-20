class AddStatusToProductLines < ActiveRecord::Migration[8.1]
  def change
    add_column :product_lines, :status, :string, null: false, default: "draft"
  end
end
