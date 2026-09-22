require "test_helper"

# Handoff 0057 -- License with NULL access_ends_at (the policy's "expires_at")
# never expires; one-time offers exist only for products that belong to a ProductLine (0065).
class IndefiniteLicenseTest < ActiveSupport::TestCase
  KST = Commerce::PeriodCalculator::KST

  setup do
    Commerce::CatalogBootstrap.call!
    @user = User.create!(name: "구매자", email: "indef-#{SecureRandom.hex(3)}@example.com", password: "password123")
    line = ProductLine.create!(internal_name: "A", customer_name: "제품", slug: "line-a", introduction: "소개", status: "published")
    @product = Product.create!(code: "line_a", name: "제품")
    line.update!(product: @product)
  end

  def indefinite_license(starts_on: Date.new(2026, 1, 1), **attrs)
    License.new({ user: @user, product: @product, source: "paid", status: "active", starts_on: starts_on, last_usable_on: nil, access_ends_at: nil }.merge(attrs))
  end

  test "a license with both end fields empty is valid, indefinite, and exposes expires_at as nil" do
    license = indefinite_license
    assert license.valid?, license.errors.full_messages.to_sentence
    assert license.indefinite?
    assert_nil license.expires_at
  end

  test "an indefinite license is active from its start date forever -- no cut-off date exists" do
    license = indefinite_license.tap(&:save!)
    assert_not license.active_at?(Time.utc(2025, 12, 31))
    [ Time.utc(2026, 1, 1), Time.utc(2036, 1, 1), Time.utc(2126, 1, 1), Time.utc(3026, 1, 1) ].each do |t|
      assert license.active_at?(t), "should be active at #{t}"
      assert_equal "active", license.effective_status(at: t)
    end
    assert_equal "scheduled", license.effective_status(at: Time.utc(2025, 1, 1))
  end

  test "a canceled indefinite license is never active" do
    license = indefinite_license(status: "canceled").tap(&:save!)
    assert_not license.active_at?(Time.current)
    assert_equal "canceled", license.effective_status
  end

  test "end fields must be both set or both empty -- validation and DB check constraint" do
    half = indefinite_license(last_usable_on: Date.new(2026, 12, 31))
    assert_not half.valid?
    half2 = indefinite_license(access_ends_at: KST.local(2027, 1, 1))
    assert_not half2.valid?

    assert_raises(ActiveRecord::StatementInvalid) { half.save!(validate: false) }
    assert_raises(ActiveRecord::StatementInvalid) { half2.save!(validate: false) }
  end

  test "a term product can never get an indefinite license, even by mistake" do
    chatdox = Product.find_by!(code: "chatdox")
    license = License.new(user: @user, product: chatdox, source: "paid", status: "active", starts_on: Date.new(2026, 1, 1))
    assert_not license.valid?
    assert_includes license.errors.attribute_names, :access_ends_at
    assert_raises(ActiveRecord::RecordInvalid) { license.save! }
  end

  test "term licenses are unchanged: end fields still required and still must match" do
    term = License.new(user: @user, product: Product.find_by!(code: "chatdox"), source: "paid", status: "active", starts_on: Date.new(2026, 1, 1))
    assert_not term.valid?
    term.assign_attributes(last_usable_on: Date.new(2026, 1, 31), access_ends_at: KST.local(2026, 2, 1))
    assert term.valid?
    assert_not term.indefinite?
    assert term.active_at?(KST.local(2026, 1, 15))
    assert_not term.active_at?(KST.local(2026, 2, 1))
    assert_equal "expired", term.effective_status(at: KST.local(2026, 2, 2))
    term.access_ends_at = KST.local(2026, 3, 1)
    assert_not term.valid?, "next-midnight rule must still apply"
  end

  test "only one non-canceled license per user, product and start date (DB index) -- a refunded one doesn't block a new purchase" do
    indefinite_license.save!
    assert_raises(ActiveRecord::RecordNotUnique) { indefinite_license.save!(validate: false) }
    License.last.update!(status: "canceled")
    assert indefinite_license.save
  end

  test "a one-time (no duration) offer is allowed only for a product line's product" do
    offer = @product.product_offers.new(code: "line_a-once-v1", version: 1, duration_months: nil, supply_amount: 10_000, vat_amount: 1_000, total_amount: 11_000)
    assert offer.valid?, offer.errors.full_messages.to_sentence
    assert offer.lifetime?

    legacy = Product.find_by!(code: "chatdox").product_offers.new(code: "chatdox-once", version: 1, duration_months: nil, supply_amount: 1000, vat_amount: 100, total_amount: 1100)
    assert_not legacy.valid?
    assert_includes legacy.errors.attribute_names, :duration_months

    zero = @product.product_offers.new(code: "zero", version: 1, duration_months: 0, supply_amount: 1, vat_amount: 0, total_amount: 1)
    assert_not zero.valid?, "0 months must not stand in for one-time"
  end

  test "a line product has at most one one-time offer per version" do
    @product.product_offers.create!(code: "o1", version: 1, duration_months: nil, supply_amount: 10_000, vat_amount: 1_000, total_amount: 11_000)
    dup = @product.product_offers.new(code: "o2", version: 1, duration_months: nil, supply_amount: 20_000, vat_amount: 2_000, total_amount: 22_000)
    assert_not dup.valid?
    assert_includes dup.errors.attribute_names, :version
  end

  test "existing term offers keep their rules (positive months, unique per product/version)" do
    offer = Product.find_by!(code: "chatdox").product_offers.find_by!(code: "chatdox-1m-v1")
    assert_not offer.lifetime?
    offer.duration_months = -1
    assert_not offer.valid?
  end

  test "order items snapshot no duration only for one-time offers" do
    order_item = OrderItem.new(product: @product, product_code: "x", product_name: "x", offer_code: "x", offer_version: 1, duration_months: nil,
      supply_amount: 100, vat_amount: 10, total_amount: 110, currency: "KRW")
    assert order_item.lifetime?
    order_item.valid?
    assert_not_includes order_item.errors.attribute_names, :duration_months
  end

  test "Product.standalone excludes line products and keeps the four catalog products" do
    assert_not_includes Product.standalone, @product
    assert_includes Product.standalone, Product.find_by!(code: "chatdox")
    assert @product.line_product?
    assert_not Product.find_by!(code: "chatdox").line_product?
  end
end
