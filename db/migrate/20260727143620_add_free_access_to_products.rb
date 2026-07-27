class AddFreeAccessToProducts < ActiveRecord::Migration[8.1]
  # Local, migration-scoped model -- same pattern as
  # AddMarketingFieldsToProducts, so this backfill keeps working even if
  # app/models/product.rb changes shape later.
  class Product < ActiveRecord::Base
    self.table_name = "products"
  end

  def up
    add_column :products, :free_access, :boolean, default: false, null: false

    # aistart may already exist (created by a prior round's manual seeding,
    # in dev or production) -- Commerce::CatalogBootstrap's find_or_create_by!
    # only sets attributes on the create path, so an existing row needs this
    # one-time backfill the same way tagline/landing_page_path did.
    Product.reset_column_information
    Product.where(code: "aistart").update_all(free_access: true, landing_page_path: "/content/aistart")
  end

  def down
    remove_column :products, :free_access
  end
end
