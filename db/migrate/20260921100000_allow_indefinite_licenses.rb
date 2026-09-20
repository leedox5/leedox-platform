# Handoff 0057 -- a one-time Season purchase grants an indefinite license:
# access_ends_at (the policy's "expires_at") and last_usable_on are NULL
# together, never a 100-year stand-in. Existing rows all have both set, so
# relaxing NOT NULL changes nothing for current data; the check constraint
# keeps the two columns from ever disagreeing.
class AllowIndefiniteLicenses < ActiveRecord::Migration[8.1]
  def change
    change_column_null :licenses, :access_ends_at, true
    change_column_null :licenses, :last_usable_on, true
    add_check_constraint :licenses,
      "(access_ends_at IS NULL AND last_usable_on IS NULL) OR (access_ends_at IS NOT NULL AND last_usable_on IS NOT NULL)",
      name: "licenses_period_all_or_none"

    # A Season's single one-time price is an offer with no duration.
    change_column_null :product_offers, :duration_months, true
    change_column_null :order_items, :duration_months, true
  end
end
