# Handoff 0065 (stage 1 "expand" of the Season flattening decided in 0064) --
# schema only, additive. `product_seasons` and `content_episodes.product_season_id`
# stay; nothing here changes what the running code reads, so the code that is
# live when this runs keeps working unchanged. The data move is separate
# (SeasonFlatten, run and verified by hand) -- see app/services/season_flatten.rb.
#
# One constraint is relaxed on purpose: the new code creates episodes directly
# under a ProductLine (no Season), which the old "exactly one of bundle /
# season" check would reject. The relaxed check still allows every row that
# exists today (a Season episode may carry both pointers during the transition).
class AddFlattenedProductColumns < ActiveRecord::Migration[8.1]
  OLD_CHECK = "(bundle_id IS NOT NULL AND product_season_id IS NULL) OR (bundle_id IS NULL AND product_season_id IS NOT NULL)".freeze
  NEW_CHECK = "(bundle_id IS NOT NULL AND product_season_id IS NULL AND product_line_id IS NULL) OR " \
              "(bundle_id IS NULL AND (product_season_id IS NOT NULL OR product_line_id IS NOT NULL))".freeze

  def up
    # The sellable unit is now the ProductLine: its commerce Product (1:1) and its
    # public reach live here instead of on a Season.
    add_reference :product_lines, :product, null: true, foreign_key: true, index: { unique: true }
    add_column :product_lines, :visibility, :string, null: false, default: "public"

    # "Same series" is a loose, optional relation between independent products.
    add_column :product_lines, :series_key, :string
    add_column :product_lines, :series_label, :string
    add_column :product_lines, :series_position, :integer, null: false, default: 0
    add_index :product_lines, :series_key

    # Which Season a line came from: drives the permanent redirects from the old
    # Season URLs and lets the data move be undone. Not a foreign key: the
    # product_seasons table is dropped in the contract step.
    add_column :product_lines, :legacy_season_id, :bigint
    add_index :product_lines, :legacy_season_id, unique: true

    add_reference :content_episodes, :product_line, null: true, foreign_key: true, index: false
    add_index :content_episodes, %i[product_line_id position], unique: true

    remove_check_constraint :content_episodes, name: "content_episodes_exactly_one_parent"
    add_check_constraint :content_episodes, NEW_CHECK, name: "content_episodes_one_parent"
  end

  def down
    orphans = select_value("SELECT COUNT(*) FROM content_episodes WHERE bundle_id IS NULL AND product_season_id IS NULL AND product_line_id IS NOT NULL").to_i
    if orphans.positive?
      raise ActiveRecord::IrreversibleMigration,
        "#{orphans} episode(s) live directly under a ProductLine (created after the flattening) and have no Season to go back to"
    end

    remove_check_constraint :content_episodes, name: "content_episodes_one_parent"
    add_check_constraint :content_episodes, OLD_CHECK, name: "content_episodes_exactly_one_parent"
    remove_index :content_episodes, %i[product_line_id position]
    remove_reference :content_episodes, :product_line, foreign_key: true

    remove_index :product_lines, :legacy_season_id
    remove_column :product_lines, :legacy_season_id
    remove_index :product_lines, :series_key
    remove_column :product_lines, :series_position
    remove_column :product_lines, :series_label
    remove_column :product_lines, :series_key
    remove_column :product_lines, :visibility
    remove_reference :product_lines, :product, foreign_key: true, index: { unique: true }
  end
end
