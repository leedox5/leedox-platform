class CreateContentBundles < ActiveRecord::Migration[8.1]
  def change
    create_table :content_bundles do |t|
      t.references :product, null: true, foreign_key: true
      t.references :owner, null: true, foreign_key: { to_table: :users }
      t.string :internal_name, null: false
      t.string :customer_title
      t.string :visibility, null: false, default: "public"
      t.string :status, null: false, default: "draft"
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
