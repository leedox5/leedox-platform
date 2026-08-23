class ExcludeCanceledFromLicenseUniqueStartIndex < ActiveRecord::Migration[8.1]
  # The old index blocked ANY future license for a user+product+start-date
  # once a canceled license had ever occupied that exact date -- a canceled
  # license shouldn't reserve anything (see License#not_canceled, used
  # everywhere else stacking/uniqueness actually matters), but this index
  # didn't know that. Discovered 2026-08-24: a real, successfully-paid
  # KakaoPay checkout for support@leedox.kr got rejected by Postgres because
  # a stale canceled coupon-grant (from earlier QA free-grant testing) had
  # already claimed today's date.
  def up
    remove_index :licenses, name: "index_licenses_on_user_product_start"
    add_index :licenses, %i[user_id product_id starts_on], unique: true,
      where: "status != 'canceled'", name: "index_licenses_on_user_product_start"
  end

  def down
    remove_index :licenses, name: "index_licenses_on_user_product_start"
    add_index :licenses, %i[user_id product_id starts_on], unique: true,
      name: "index_licenses_on_user_product_start"
  end
end
