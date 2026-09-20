# Handoff 0056 R2 -- the long-lived customer-facing "product" (e.g. "Codex
# TODO") that groups one or more Season commerce Products together. See
# result.md §3 for why this is a new, separate model rather than repurposing
# commerce Product itself: Product/License/OrderItem all treat a single
# Product as the access unit, so each Season stays its own Product row and
# ProductLine is the lightweight wrapper around them.
class CreateProductLines < ActiveRecord::Migration[8.1]
  def change
    create_table :product_lines do |t|
      t.string :internal_name, null: false
      t.string :customer_name, null: false
      t.string :slug, null: false
      t.text :problem, null: false
      t.text :expected_result, null: false
      t.text :target_audience, null: false
      t.string :ai_supporter

      t.timestamps
    end

    add_index :product_lines, :slug, unique: true
  end
end
