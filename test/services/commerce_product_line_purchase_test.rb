require "test_helper"

# Handoff 0057 / 0065 -- per-product one-time price, sale switch, purchase, access and
# refund revocation, end to end at the service level.
class CommerceProductLinePurchaseTest < ActiveSupport::TestCase
  KST = Commerce::PeriodCalculator::KST

  setup do
    Commerce::CatalogBootstrap.call!
    @previous_flag = ENV["LEEDOX_COMMERCE_ENABLED"]
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    @admin = User.create!(name: "관리자", email: "pl-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @buyer = User.create!(name: "구매자", email: "pl-buyer-#{SecureRandom.hex(3)}@example.com", password: "password123")
    @other = User.create!(name: "다른사람", email: "pl-other-#{SecureRandom.hex(3)}@example.com", password: "password123")
    @line = ProductLine.create!(internal_name: "A", customer_name: "제품 A", slug: "product-a", introduction: "소개", status: "published")
    @line2 = ProductLine.create!(internal_name: "B", customer_name: "제품 B", slug: "product-b", introduction: "소개", status: "published", series_key: "grp")
  end

  teardown do
    @previous_flag.nil? ? ENV.delete("LEEDOX_COMMERCE_ENABLED") : ENV["LEEDOX_COMMERCE_ENABLED"] = @previous_flag
  end

  def price!(line, amount = 33_000)
    Commerce::ProductLineSales.set_price!(product_line: line, total_amount: amount, actor: @admin)
  end

  def open_sale!(line, amount = 33_000)
    price!(line, amount)
    Commerce::ProductLineSales.start_sale!(product_line: line, actor: @admin)
    line.reload
  end

  def order_for(user, line, provider: "manual")
    Commerce::OrderCreator.call!(user: user, product_code: line.reload.product.code, offer_code: line.lifetime_offer.code,
      requested_start_on: nil, provider: provider)
  end

  def pay!(order)
    Commerce::ConfirmManualPayment.call!(order: order, actor: @admin)
    order.reload
  end

  def allowed?(user, line)
    Entitlements::ProductAccess.allowed?(user: user, product_code: line.reload.product.code)
  end

  # --- pricing -------------------------------------------------------------

  test "setting a price creates the product's commerce Product (1:1) with sales stopped and a one-time offer" do
    assert_nil @line.product
    offer = price!(@line, 33_000)
    @line.reload

    product = @line.product
    assert product.persisted?
    assert_equal product, offer.product
    assert_equal @line, product.product_line
    assert_not product.sale_enabled?, "a new product must start with sales stopped"
    assert product.active?
    assert_equal "product_a", product.code
    assert offer.lifetime?
    assert_nil offer.duration_months
    assert_equal [ 30_000, 3_000, 33_000 ], [ offer.supply_amount, offer.vat_amount, offer.total_amount ]
    assert_equal 33_000, @line.price
    assert_equal 1, product.product_offers.count
    assert @line.gated?
    assert_not @line.for_sale?
  end

  test "each product gets its own Product and price; A's Product is not B's" do
    price!(@line, 33_000)
    price!(@line2, 55_000)
    assert_not_equal @line.reload.product_id, @line2.reload.product_id
    assert_equal 33_000, @line.price
    assert_equal 55_000, @line2.price
  end

  test "re-saving the price edits the single offer in place and keeps past orders' snapshots" do
    open_sale!(@line, 33_000)
    order = order_for(@buyer, @line)

    price!(@line, 44_000)
    assert_equal 1, @line.reload.product.product_offers.count
    assert_equal 44_000, @line.price
    assert_equal 33_000, order.reload.total_amount
    assert_equal 33_000, order.order_items.first.total_amount
  end

  test "product code collisions get a numeric suffix" do
    Product.create!(code: "product_a", name: "이미 있음")
    price!(@line)
    assert_equal "product_a_2", @line.reload.product.code
  end

  test "invalid prices are refused and create nothing" do
    [ -5, "abc", "", nil, "1.5" ].each do |bad|
      assert_raises(Commerce::ProductLineSales::Invalid) { price!(@line, bad) }
    end
    assert_nil @line.reload.product
    assert_equal 0, ProductOffer.lifetime.count
  end

  test "pricing and sale changes are admin-only" do
    assert_raises(Pundit::NotAuthorizedError) { Commerce::ProductLineSales.set_price!(product_line: @line, total_amount: 1000, actor: @buyer) }
    price!(@line)
    assert_raises(Pundit::NotAuthorizedError) { Commerce::ProductLineSales.start_sale!(product_line: @line, actor: @buyer) }
    assert_raises(Pundit::NotAuthorizedError) { Commerce::ProductLineSales.stop_sale!(product_line: @line, actor: nil) }
  end

  test "price and sale changes are audit-logged" do
    price!(@line, 33_000)
    Commerce::ProductLineSales.start_sale!(product_line: @line, actor: @admin)
    Commerce::ProductLineSales.stop_sale!(product_line: @line, actor: @admin)
    actions = CommerceAuditEvent.where(auditable: @line.reload.product).order(:id).pluck(:action, :to_state)
    assert_equal [ [ "product_pricing_updated", "33000" ], [ "product_sale_toggled", "true" ], [ "product_sale_toggled", "false" ] ], actions
  end

  # --- 0-won (free) products --------------------------------------------------

  def claim!(user, line)
    Commerce::ClaimFreeAccess.call!(user: user, product_line: line.reload)
  end

  test "0 is a valid price: a free product with a zero offer, sales stopped, nothing orderable" do
    offer = price!(@line, 0)
    assert_equal [ 0, 0, 0 ], [ offer.supply_amount, offer.vat_amount, offer.total_amount ]
    assert offer.lifetime?
    assert @line.reload.free?
    assert @line.gated?
    assert_not @line.product.sale_enabled?
    assert_not @line.free_start_open?, "free start must wait for the explicit admin action too"
    assert_not @line.for_sale?
  end

  test "a free product can be started by a user only after the admin opens it, with no order, payment record or provider" do
    price!(@line, 0)
    assert_raises(Commerce::ClaimFreeAccess::Unavailable) { claim!(@buyer, @line) }

    Commerce::ProductLineSales.start_sale!(product_line: @line, actor: @admin)
    assert @line.reload.free_start_open?
    assert_no_difference [ "Order.count", "OrderItem.count", "PaymentTransaction.count" ] do
      assert_difference "License.count", 1 do
        result = claim!(@buyer, @line)
        assert result.created
        license = result.license
        assert_equal "free", license.source
        assert_equal "active", license.status
        assert license.indefinite?
        assert_nil license.order_item
        assert_equal Time.current.in_time_zone(KST).to_date, license.starts_on
      end
    end
    assert allowed?(@buyer, @line)
    audit = CommerceAuditEvent.find_by!(action: "season_free_access_claimed")
    assert_equal @buyer, audit.actor
    assert_equal @buyer.licenses.sole, audit.auditable
  end

  test "pressing free start twice (or in two tabs) never creates a second license" do
    open_sale!(@line, 0)
    first = claim!(@buyer, @line)
    assert_no_difference "License.count" do
      again = claim!(@buyer, @line)
      assert_not again.created
      assert_equal first.license, again.license
    end
    assert_equal 1, @buyer.licenses.where(product: @line.product).count
  end

  test "the DB itself refuses a duplicate active free license for the same user, product and day" do
    open_sale!(@line, 0)
    claim!(@buyer, @line)
    dup = License.new(user: @buyer, product: @line.product, source: "free", status: "active", starts_on: Time.current.in_time_zone(KST).to_date)
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save!(validate: false) }
  end

  test "a free product is never orderable: no zero-amount order is ever created" do
    open_sale!(@line, 0)
    assert_no_difference [ "Order.count", "PaymentTransaction.count" ] do
      error = assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@buyer, @line) }
      assert_match(/free product/, error.message)
    end
  end

  test "free start needs no payment provider: the global commerce switch doesn't apply" do
    open_sale!(@line, 0)
    ENV["LEEDOX_COMMERCE_ENABLED"] = "false"
    assert @line.reload.free_start_open?
    assert claim!(@buyer, @line).created
    assert allowed?(@buyer, @line)
  end

  test "free start is refused for priced products, unpublished or private products, and stopped sales" do
    open_sale!(@line, 33_000)
    assert_raises(Commerce::ClaimFreeAccess::Unavailable) { claim!(@buyer, @line) }

    open_sale!(@line2, 0)
    @line2.update!(visibility: "private")
    assert_raises(Commerce::ClaimFreeAccess::Unavailable) { claim!(@buyer, @line2) }
    @line2.update!(visibility: "public", status: "draft")
    assert_raises(Commerce::ClaimFreeAccess::Unavailable) { claim!(@buyer, @line2) }
    @line2.update!(status: "published")
    Commerce::ProductLineSales.stop_sale!(product_line: @line2, actor: @admin)
    assert_raises(Commerce::ClaimFreeAccess::Unavailable) { claim!(@buyer, @line2.reload) }
  end

  test "stopping a free product blocks new starts only; people who already started keep access" do
    open_sale!(@line, 0)
    claim!(@buyer, @line)
    Commerce::ProductLineSales.stop_sale!(product_line: @line, actor: @admin)
    assert_raises(Commerce::ClaimFreeAccess::Unavailable) { claim!(@other, @line.reload) }
    assert allowed?(@buyer, @line)
    assert_not allowed?(@other, @line)
  end

  test "starting free S01 opens only S01: no inheritance to a paid S02, and no free-for-all across users" do
    open_sale!(@line, 0)
    open_sale!(@line2, 55_000)
    claim!(@buyer, @line)
    assert allowed?(@buyer, @line)
    assert_not allowed?(@buyer, @line2)
    assert_not allowed?(@other, @line)
  end

  test "changing a price never touches licenses already issued, in either direction" do
    open_sale!(@line, 0)
    claim!(@buyer, @line)
    price!(@line, 33_000)
    assert allowed?(@buyer, @line), "free starter keeps access after S01 becomes paid"
    assert_raises(Commerce::ClaimFreeAccess::Unavailable) { claim!(@other, @line.reload) }
    assert_equal 1, @line.reload.product.product_offers.count

    Commerce::ProductLineSales.start_sale!(product_line: @line, actor: @admin)
    pay!(order_for(@other, @line))
    price!(@line, 0)
    assert allowed?(@other, @line), "paid owner keeps access after S01 becomes free"
    assert_not @line.reload.free_start_open?, "going free stops the sale until an admin re-opens it"
    Commerce::ProductLineSales.start_sale!(product_line: @line, actor: @admin)
    assert @line.reload.free_start_open?
    assert claim!(User.create!(name: "새사람", email: "new-#{SecureRandom.hex(3)}@example.com", password: "password123"), @line).created
  end

  test "switching between paid and free stops the sale so a typo can't give a product away or start charging" do
    open_sale!(@line, 33_000)
    price!(@line, 0)
    assert_not @line.reload.product.sale_enabled?
    assert_not @line.free_start_open?
    assert_raises(Commerce::ClaimFreeAccess::Unavailable) { claim!(@buyer, @line) }

    Commerce::ProductLineSales.start_sale!(product_line: @line, actor: @admin)
    price!(@line, 11_000)
    assert_not @line.reload.product.sale_enabled?, "free -> paid stops it too"
    assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@buyer, @line) }
    toggles = CommerceAuditEvent.where(auditable: @line.product, action: "product_sale_toggled").order(:id).pluck(:to_state)
    assert_equal %w[true false true false], toggles, "every automatic stop is audit-logged like a manual one"
  end

  test "paid to paid price changes leave the sale switch exactly as it was" do
    open_sale!(@line, 33_000)
    price!(@line, 44_000)
    assert @line.reload.product.sale_enabled?
    Commerce::ProductLineSales.stop_sale!(product_line: @line, actor: @admin)
    price!(@line, 22_000)
    assert_not @line.reload.product.sale_enabled?
  end

  test "a free-started license is not an order: it has no refund path and reconciliation stays clean" do
    open_sale!(@line, 0)
    license = claim!(@buyer, @line).license
    assert_empty license.user.orders
    assert_nothing_raised { Commerce::Reconciliation.call }
  end

  # --- sale switch ---------------------------------------------------------

  test "selling requires a saved price and a published, non-private product" do
    assert_raises(Commerce::ProductLineSales::Invalid) { Commerce::ProductLineSales.start_sale!(product_line: @line, actor: @admin) }

    price!(@line)
    @line.update!(visibility: "private")
    assert_raises(Commerce::ProductLineSales::Invalid) { Commerce::ProductLineSales.start_sale!(product_line: @line, actor: @admin) }
    @line.update!(visibility: "public", status: "draft")
    assert_raises(Commerce::ProductLineSales::Invalid) { Commerce::ProductLineSales.start_sale!(product_line: @line, actor: @admin) }
    @line.update!(status: "published")

    Commerce::ProductLineSales.start_sale!(product_line: @line, actor: @admin)
    assert @line.reload.for_sale?
  end

  test "the global commerce switch still gates sales" do
    open_sale!(@line)
    assert @line.for_sale?
    ENV["LEEDOX_COMMERCE_ENABLED"] = "false"
    assert_not @line.for_sale?
    assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@buyer, @line) }
  end

  test "stopped or unpriced products can't be ordered" do
    price!(@line)
    assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@buyer, @line) }
    Commerce::ProductLineSales.start_sale!(product_line: @line, actor: @admin)
    assert order_for(@buyer, @line.reload)
    Commerce::ProductLineSales.stop_sale!(product_line: @line, actor: @admin)
    assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@other, @line.reload) }
  end

  test "a product that became unpublished or private since sales started can no longer be ordered" do
    open_sale!(@line)
    @line.update!(visibility: "private")
    assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@buyer, @line) }
    @line.update!(visibility: "public", status: "unpublished")
    assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@buyer, @line) }
  end

  # --- purchase and indefinite license --------------------------------------

  test "a one-time order has no duration or period; paying it issues one indefinite, active license" do
    open_sale!(@line)
    order = order_for(@buyer, @line)
    item = order.order_items.sole
    assert item.lifetime?
    assert_nil item.duration_months
    assert_equal 33_000, order.total_amount
    assert_equal Time.current.in_time_zone(KST).to_date, order.requested_start_on

    assert_difference "License.count", 1 do
      pay!(order)
    end
    license = order.licenses.sole
    assert_equal "paid", license.source
    assert_equal "active", license.status
    assert license.indefinite?
    assert_nil license.access_ends_at
    assert_nil license.last_usable_on
    assert_equal Time.current.in_time_zone(KST).to_date, license.starts_on
    assert allowed?(@buyer, @line)
  end

  test "a replayed payment confirmation can't issue a second license" do
    open_sale!(@line)
    order = order_for(@buyer, @line)
    pay!(order)
    order_item = order.order_items.sole
    assert_no_difference "License.count" do
      Commerce::LicenseScheduler.create_for!(user: @buyer, order_item: order_item, requested_start_on: order.requested_start_on)
    end
  end

  test "a buyer can't order a product they already own; a refunded (canceled) one can be bought again" do
    open_sale!(@line)
    pay!(order_for(@buyer, @line))
    assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@buyer, @line) }

    @buyer.licenses.each { |l| l.update!(status: "canceled") }
    assert_not allowed?(@buyer, @line)
    again = order_for(@buyer, @line)
    pay!(again)
    assert allowed?(@buyer, @line)
  end

  # --- entitlement boundaries ----------------------------------------------

  test "buying S01 opens only S01: no inheritance to S02, other users, or the four term products" do
    open_sale!(@line)
    open_sale!(@line2, 55_000)
    pay!(order_for(@buyer, @line))

    assert allowed?(@buyer, @line)
    assert_not allowed?(@buyer, @line2), "S01 purchase must not open S02"
    assert_not allowed?(@other, @line), "another user must not get the license"
    assert_not Entitlements::ProductAccess.allowed?(user: @buyer, product_code: "chatdox")

    pay!(order_for(@buyer, @line2))
    assert allowed?(@buyer, @line2), "S02 is opened only by its own purchase"
  end

  test "stopping a sale blocks new purchases only -- existing owners keep access, even far in the future" do
    open_sale!(@line)
    pay!(order_for(@buyer, @line))

    Commerce::ProductLineSales.stop_sale!(product_line: @line, actor: @admin)
    assert_not @line.reload.product.sale_enabled?
    assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@other, @line) }
    assert allowed?(@buyer, @line)
    assert Entitlements::ProductAccess.allowed?(user: @buyer, product_code: @line.product.code, at: Time.current + 50.years)
  end

  test "releasing another product or changing A's price leaves A owners' licenses untouched" do
    open_sale!(@line)
    order = pay!(order_for(@buyer, @line))
    license = order.licenses.sole

    open_sale!(@line2, 99_000)
    price!(@line, 77_000)
    license.reload
    assert_equal "active", license.status
    assert license.indefinite?
    assert allowed?(@buyer, @line)
  end

  # --- refund --------------------------------------------------------------

  test "an approved refund revokes only the refunded product's license" do
    open_sale!(@line)
    open_sale!(@line2, 55_000)
    order1 = pay!(order_for(@buyer, @line))
    order2 = pay!(order_for(@buyer, @line2))
    request = Commerce::RefundRequestSubmission.call!(user: @buyer, order: order1, reason_code: "other", customer_note: "환불")
    %w[start_review approve mark_processing].each { |action| Commerce::RefundRequestTransition.call!(refund_request: request, actor: @admin, action: action) }

    Commerce::ConfirmRefund.call!(refund_request: request.reload, actor: @admin)

    assert_equal "canceled", order1.licenses.sole.status
    assert_not allowed?(@buyer, @line)
    assert_equal "active", order2.licenses.sole.reload.status
    assert allowed?(@buyer, @line2), "the other product's license must survive"
  end

  test "reconciliation runs cleanly with an indefinite license present" do
    open_sale!(@line)
    pay!(order_for(@buyer, @line))
    assert_nothing_raised { Commerce::Reconciliation.call }
  end

  # --- existing term products are untouched ---------------------------------

  test "a normal term purchase still gets a finite license with the exact dates it always did" do
    Product.find_by!(code: "chatdox").update!(sale_enabled: true)
    today = Time.current.in_time_zone(KST).to_date
    order = Commerce::OrderCreator.call!(user: @buyer, product_code: "chatdox", offer_code: "chatdox-1m-v1", requested_start_on: today, provider: "manual")
    assert_equal 1, order.order_items.sole.duration_months
    pay!(order)
    license = order.licenses.sole
    assert_not license.indefinite?
    expected = Commerce::PeriodCalculator.call(start_on: today, duration_months: 1)
    assert_equal expected.last_usable_on, license.last_usable_on
    assert_equal expected.access_ends_at, license.access_ends_at
  end
end
