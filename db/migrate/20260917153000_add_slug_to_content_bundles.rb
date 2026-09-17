# Handoff 0055 -- lets each ContentBundle own its own 01..N episode
# numbering scope for customer URLs (/content/:product_code/:bundle_slug/:id)
# instead of ProductContent::DatabaseSource flattening every bundle under a
# product into one position-keyed list, which collided once a second bundle
# existed (see result.md §2).
#
# Nullable: a draft bundle not yet connected to a Product doesn't need a
# slug (ContentBundle validates presence only once product_id is set -- see
# app/models/content_bundle.rb). Unique per product, not globally, so two
# different products could each have their own "intro" bundle.
class AddSlugToContentBundles < ActiveRecord::Migration[8.1]
  def change
    add_column :content_bundles, :slug, :string
    add_index :content_bundles, %i[product_id slug], unique: true
  end
end
