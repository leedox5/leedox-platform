require "test_helper"

# Handoff 0057 -- per-Season one-time price, sale switch, purchase, access and
# refund revocation, end to end at the service level.
class CommerceSeasonPurchaseTest < ActiveSupport::TestCase
  KST = Commerce::PeriodCalculator::KST

  setup do
    Commerce::CatalogBootstrap.call!
    @previous_flag = ENV["LEEDOX_COMMERCE_ENABLED"]
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    @admin = User.create!(name: "관리자", email: "season-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @buyer = User.create!(name: "구매자", email: "season-buyer-#{SecureRandom.hex(3)}@example.com", password: "password123")
    @other = User.create!(name: "다른사람", email: "season-other-#{SecureRandom.hex(3)}@example.com", password: "password123")
    @line = ProductLine.create!(internal_name: "A", customer_name: "제품 A", slug: "product-a", introduction: "소개", status: "published")
    @s1 = @line.product_seasons.create!(internal_name: "S01", season_code: "S01", slug: "s01", status: "published", visibility: "public")
    @s2 = @line.product_seasons.create!(internal_name: "S02", season_code: "S02", slug: "s02", status: "published", visibility: "public")
  end

  teardown do
    @previous_flag.nil? ? ENV.delete("LEEDOX_COMMERCE_ENABLED") : ENV["LEEDOX_COMMERCE_ENABLED"] = @previous_flag
  end

  def price!(season, amount = 33_000)
    Commerce::SeasonSales.set_price!(season: season, total_amount: amount, actor: @admin)
  end

  def open_sale!(season, amount = 33_000)
    price!(season, amount)
    Commerce::SeasonSales.start_sale!(season: season, actor: @admin)
    season.reload
  end

  def order_for(user, season, provider: "manual")
    Commerce::OrderCreator.call!(user: user, product_code: season.reload.product.code, offer_code: season.lifetime_offer.code,
      requested_start_on: nil, provider: provider)
  end

  def pay!(order)
    Commerce::ConfirmManualPayment.call!(order: order, actor: @admin)
    order.reload
  end

  def allowed?(user, season)
    Entitlements::ProductAccess.allowed?(user: user, product_code: season.reload.product.code)
  end

  # --- pricing -------------------------------------------------------------

  test "setting a price creates the Season's commerce Product (1:1) with sales stopped and a one-time offer" do
    assert_nil @s1.product
    offer = price!(@s1, 33_000)
    @s1.reload

    product = @s1.product
    assert product.persisted?
    assert_equal product, offer.product
    assert_equal @s1, product.product_season
    assert_not product.sale_enabled?, "new Season must start with sales stopped"
    assert product.active?
    assert_equal "product_a_s01", product.code
    assert offer.lifetime?
    assert_nil offer.duration_months
    assert_equal [ 30_000, 3_000, 33_000 ], [ offer.supply_amount, offer.vat_amount, offer.total_amount ]
    assert_equal 33_000, @s1.price
    assert_equal 1, product.product_offers.count
    assert @s1.gated?
    assert_not @s1.for_sale?
  end

  test "each Season gets its own Product and price; S01's Product is not S02's" do
    price!(@s1, 33_000)
    price!(@s2, 55_000)
    assert_not_equal @s1.reload.product_id, @s2.reload.product_id
    assert_equal 33_000, @s1.price
    assert_equal 55_000, @s2.price
  end

  test "re-saving the price edits the single offer in place and keeps past orders' snapshots" do
    open_sale!(@s1, 33_000)
    order = order_for(@buyer, @s1)

    price!(@s1, 44_000)
    assert_equal 1, @s1.reload.product.product_offers.count
    assert_equal 44_000, @s1.price
    assert_equal 33_000, order.reload.total_amount
    assert_equal 33_000, order.order_items.first.total_amount
  end

  test "product code collisions get a numeric suffix" do
    Product.create!(code: "product_a_s01", name: "이미 있음")
    price!(@s1)
    assert_equal "product_a_s01_2", @s1.reload.product.code
  end

  test "invalid prices are refused and create nothing" do
    [ -5, "abc", "", nil, "1.5" ].each do |bad|
      assert_raises(Commerce::SeasonSales::Invalid) { price!(@s1, bad) }
    end
    assert_nil @s1.reload.product
    assert_equal 0, ProductOffer.lifetime.count
  end

  test "pricing and sale changes are admin-only" do
    assert_raises(Pundit::NotAuthorizedError) { Commerce::SeasonSales.set_price!(season: @s1, total_amount: 1000, actor: @buyer) }
    price!(@s1)
    assert_raises(Pundit::NotAuthorizedError) { Commerce::SeasonSales.start_sale!(season: @s1, actor: @buyer) }
    assert_raises(Pundit::NotAuthorizedError) { Commerce::SeasonSales.stop_sale!(season: @s1, actor: nil) }
  end

  test "price and sale changes are audit-logged" do
    price!(@s1, 33_000)
    Commerce::SeasonSales.start_sale!(season: @s1, actor: @admin)
    Commerce::SeasonSales.stop_sale!(season: @s1, actor: @admin)
    actions = CommerceAuditEvent.where(auditable: @s1.reload.product).order(:id).pluck(:action, :to_state)
    assert_equal [ [ "product_pricing_updated", "33000" ], [ "product_sale_toggled", "true" ], [ "product_sale_toggled", "false" ] ], actions
  end

  # --- 0-won (free) Seasons --------------------------------------------------

  def claim!(user, season)
    Commerce::ClaimFreeSeason.call!(user: user, season: season.reload)
  end

  test "0 is a valid price: a free Season with a zero offer, sales stopped, nothing orderable" do
    offer = price!(@s1, 0)
    assert_equal [ 0, 0, 0 ], [ offer.supply_amount, offer.vat_amount, offer.total_amount ]
    assert offer.lifetime?
    assert @s1.reload.free?
    assert @s1.gated?
    assert_not @s1.product.sale_enabled?
    assert_not @s1.free_start_open?, "free start must wait for the explicit admin action too"
    assert_not @s1.for_sale?
  end

  test "a free Season can be started by a user only after the admin opens it, with no order, payment record or provider" do
    price!(@s1, 0)
    assert_raises(Commerce::ClaimFreeSeason::Unavailable) { claim!(@buyer, @s1) }

    Commerce::SeasonSales.start_sale!(season: @s1, actor: @admin)
    assert @s1.reload.free_start_open?
    assert_no_difference [ "Order.count", "OrderItem.count", "PaymentTransaction.count" ] do
      assert_difference "License.count", 1 do
        result = claim!(@buyer, @s1)
        assert result.created
        license = result.license
        assert_equal "free", license.source
        assert_equal "active", license.status
        assert license.indefinite?
        assert_nil license.order_item
        assert_equal Time.current.in_time_zone(KST).to_date, license.starts_on
      end
    end
    assert allowed?(@buyer, @s1)
    audit = CommerceAuditEvent.find_by!(action: "season_free_access_claimed")
    assert_equal @buyer, audit.actor
    assert_equal @buyer.licenses.sole, audit.auditable
  end

  test "pressing free start twice (or in two tabs) never creates a second license" do
    open_sale!(@s1, 0)
    first = claim!(@buyer, @s1)
    assert_no_difference "License.count" do
      again = claim!(@buyer, @s1)
      assert_not again.created
      assert_equal first.license, again.license
    end
    assert_equal 1, @buyer.licenses.where(product: @s1.product).count
  end

  test "the DB itself refuses a duplicate active free license for the same user, Season and day" do
    open_sale!(@s1, 0)
    claim!(@buyer, @s1)
    dup = License.new(user: @buyer, product: @s1.product, source: "free", status: "active", starts_on: Time.current.in_time_zone(KST).to_date)
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save!(validate: false) }
  end

  test "a free Season is never orderable: no zero-amount order is ever created" do
    open_sale!(@s1, 0)
    assert_no_difference [ "Order.count", "PaymentTransaction.count" ] do
      error = assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@buyer, @s1) }
      assert_match(/free season/, error.message)
    end
  end

  test "free start needs no payment provider: the global commerce switch doesn't apply" do
    open_sale!(@s1, 0)
    ENV["LEEDOX_COMMERCE_ENABLED"] = "false"
    assert @s1.reload.free_start_open?
    assert claim!(@buyer, @s1).created
    assert allowed?(@buyer, @s1)
  end

  test "free start is refused for priced Seasons, unpublished or private Seasons, and stopped sales" do
    open_sale!(@s1, 33_000)
    assert_raises(Commerce::ClaimFreeSeason::Unavailable) { claim!(@buyer, @s1) }

    open_sale!(@s2, 0)
    @s2.update!(visibility: "private")
    assert_raises(Commerce::ClaimFreeSeason::Unavailable) { claim!(@buyer, @s2) }
    @s2.update!(visibility: "public", status: "draft")
    assert_raises(Commerce::ClaimFreeSeason::Unavailable) { claim!(@buyer, @s2) }
    @s2.update!(status: "published")
    @line.update!(status: "draft")
    assert_raises(Commerce::ClaimFreeSeason::Unavailable) { claim!(@buyer, @s2) }
    @line.update!(status: "published")
    Commerce::SeasonSales.stop_sale!(season: @s2, actor: @admin)
    assert_raises(Commerce::ClaimFreeSeason::Unavailable) { claim!(@buyer, @s2.reload) }
  end

  test "stopping a free Season blocks new starts only; people who already started keep access" do
    open_sale!(@s1, 0)
    claim!(@buyer, @s1)
    Commerce::SeasonSales.stop_sale!(season: @s1, actor: @admin)
    assert_raises(Commerce::ClaimFreeSeason::Unavailable) { claim!(@other, @s1.reload) }
    assert allowed?(@buyer, @s1)
    assert_not allowed?(@other, @s1)
  end

  test "starting free S01 opens only S01: no inheritance to a paid S02, and no free-for-all across users" do
    open_sale!(@s1, 0)
    open_sale!(@s2, 55_000)
    claim!(@buyer, @s1)
    assert allowed?(@buyer, @s1)
    assert_not allowed?(@buyer, @s2)
    assert_not allowed?(@other, @s1)
  end

  test "changing a price never touches licenses already issued, in either direction" do
    open_sale!(@s1, 0)
    claim!(@buyer, @s1)
    price!(@s1, 33_000)
    assert allowed?(@buyer, @s1), "free starter keeps access after S01 becomes paid"
    assert_raises(Commerce::ClaimFreeSeason::Unavailable) { claim!(@other, @s1.reload) }
    assert_equal 1, @s1.reload.product.product_offers.count

    Commerce::SeasonSales.start_sale!(season: @s1, actor: @admin)
    pay!(order_for(@other, @s1))
    price!(@s1, 0)
    assert allowed?(@other, @s1), "paid owner keeps access after S01 becomes free"
    assert_not @s1.reload.free_start_open?, "going free stops the sale until an admin re-opens it"
    Commerce::SeasonSales.start_sale!(season: @s1, actor: @admin)
    assert @s1.reload.free_start_open?
    assert claim!(User.create!(name: "새사람", email: "new-#{SecureRandom.hex(3)}@example.com", password: "password123"), @s1).created
  end

  test "switching between paid and free stops the sale so a typo can't give a Season away or start charging" do
    open_sale!(@s1, 33_000)
    price!(@s1, 0)
    assert_not @s1.reload.product.sale_enabled?
    assert_not @s1.free_start_open?
    assert_raises(Commerce::ClaimFreeSeason::Unavailable) { claim!(@buyer, @s1) }

    Commerce::SeasonSales.start_sale!(season: @s1, actor: @admin)
    price!(@s1, 11_000)
    assert_not @s1.reload.product.sale_enabled?, "free -> paid stops it too"
    assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@buyer, @s1) }
    toggles = CommerceAuditEvent.where(auditable: @s1.product, action: "product_sale_toggled").order(:id).pluck(:to_state)
    assert_equal %w[true false true false], toggles, "every automatic stop is audit-logged like a manual one"
  end

  test "paid to paid price changes leave the sale switch exactly as it was" do
    open_sale!(@s1, 33_000)
    price!(@s1, 44_000)
    assert @s1.reload.product.sale_enabled?
    Commerce::SeasonSales.stop_sale!(season: @s1, actor: @admin)
    price!(@s1, 22_000)
    assert_not @s1.reload.product.sale_enabled?
  end

  test "a free-started license is not an order: it has no refund path and reconciliation stays clean" do
    open_sale!(@s1, 0)
    license = claim!(@buyer, @s1).license
    assert_empty license.user.orders
    assert_nothing_raised { Commerce::Reconciliation.call }
  end

  # --- sale switch ---------------------------------------------------------

  test "selling requires a saved price and a published, non-private Season and product" do
    assert_raises(Commerce::SeasonSales::Invalid) { Commerce::SeasonSales.start_sale!(season: @s1, actor: @admin) }

    price!(@s1)
    @s1.update!(visibility: "private")
    assert_raises(Commerce::SeasonSales::Invalid) { Commerce::SeasonSales.start_sale!(season: @s1, actor: @admin) }
    @s1.update!(visibility: "public", status: "draft")
    assert_raises(Commerce::SeasonSales::Invalid) { Commerce::SeasonSales.start_sale!(season: @s1, actor: @admin) }
    @s1.update!(status: "published")
    @line.update!(status: "draft")
    assert_raises(Commerce::SeasonSales::Invalid) { Commerce::SeasonSales.start_sale!(season: @s1, actor: @admin) }
    @line.update!(status: "published")

    Commerce::SeasonSales.start_sale!(season: @s1, actor: @admin)
    assert @s1.reload.for_sale?
  end

  test "the global commerce switch still gates sales" do
    open_sale!(@s1)
    assert @s1.for_sale?
    ENV["LEEDOX_COMMERCE_ENABLED"] = "false"
    assert_not @s1.for_sale?
    assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@buyer, @s1) }
  end

  test "stopped or unpriced Seasons can't be ordered" do
    price!(@s1)
    assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@buyer, @s1) }
    Commerce::SeasonSales.start_sale!(season: @s1, actor: @admin)
    assert order_for(@buyer, @s1.reload)
    Commerce::SeasonSales.stop_sale!(season: @s1, actor: @admin)
    assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@other, @s1.reload) }
  end

  test "a Season that became unpublished or private since sales started can no longer be ordered" do
    open_sale!(@s1)
    @s1.update!(visibility: "private")
    assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@buyer, @s1) }
    @s1.update!(visibility: "public", status: "unpublished")
    assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@buyer, @s1) }
  end

  # --- purchase and indefinite license --------------------------------------

  test "a one-time order has no duration or period; paying it issues one indefinite, active license" do
    open_sale!(@s1)
    order = order_for(@buyer, @s1)
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
    assert allowed?(@buyer, @s1)
  end

  test "a replayed payment confirmation can't issue a second license" do
    open_sale!(@s1)
    order = order_for(@buyer, @s1)
    pay!(order)
    order_item = order.order_items.sole
    assert_no_difference "License.count" do
      Commerce::LicenseScheduler.create_for!(user: @buyer, order_item: order_item, requested_start_on: order.requested_start_on)
    end
  end

  test "a buyer can't order a Season they already own; a refunded (canceled) one can be bought again" do
    open_sale!(@s1)
    pay!(order_for(@buyer, @s1))
    assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@buyer, @s1) }

    @buyer.licenses.each { |l| l.update!(status: "canceled") }
    assert_not allowed?(@buyer, @s1)
    again = order_for(@buyer, @s1)
    pay!(again)
    assert allowed?(@buyer, @s1)
  end

  # --- entitlement boundaries ----------------------------------------------

  test "buying S01 opens only S01: no inheritance to S02, other users, or the four term products" do
    open_sale!(@s1)
    open_sale!(@s2, 55_000)
    pay!(order_for(@buyer, @s1))

    assert allowed?(@buyer, @s1)
    assert_not allowed?(@buyer, @s2), "S01 purchase must not open S02"
    assert_not allowed?(@other, @s1), "another user must not get the license"
    assert_not Entitlements::ProductAccess.allowed?(user: @buyer, product_code: "chatdox")

    pay!(order_for(@buyer, @s2))
    assert allowed?(@buyer, @s2), "S02 is opened only by its own purchase"
  end

  test "stopping a sale blocks new purchases only -- existing owners keep access, even far in the future" do
    open_sale!(@s1)
    pay!(order_for(@buyer, @s1))

    Commerce::SeasonSales.stop_sale!(season: @s1, actor: @admin)
    assert_not @s1.reload.product.sale_enabled?
    assert_raises(Commerce::OrderCreator::Unavailable) { order_for(@other, @s1) }
    assert allowed?(@buyer, @s1)
    assert Entitlements::ProductAccess.allowed?(user: @buyer, product_code: @s1.product.code, at: Time.current + 50.years)
  end

  test "releasing a new Season (S02) or changing S01's price leaves S01 owners' licenses untouched" do
    open_sale!(@s1)
    order = pay!(order_for(@buyer, @s1))
    license = order.licenses.sole

    open_sale!(@s2, 99_000)
    price!(@s1, 77_000)
    license.reload
    assert_equal "active", license.status
    assert license.indefinite?
    assert allowed?(@buyer, @s1)
  end

  # --- refund --------------------------------------------------------------

  test "an approved refund revokes only the refunded Season's license" do
    open_sale!(@s1)
    open_sale!(@s2, 55_000)
    order1 = pay!(order_for(@buyer, @s1))
    order2 = pay!(order_for(@buyer, @s2))
    request = Commerce::RefundRequestSubmission.call!(user: @buyer, order: order1, reason_code: "other", customer_note: "환불")
    %w[start_review approve mark_processing].each { |action| Commerce::RefundRequestTransition.call!(refund_request: request, actor: @admin, action: action) }

    Commerce::ConfirmRefund.call!(refund_request: request.reload, actor: @admin)

    assert_equal "canceled", order1.licenses.sole.status
    assert_not allowed?(@buyer, @s1)
    assert_equal "active", order2.licenses.sole.reload.status
    assert allowed?(@buyer, @s2), "the other Season's license must survive"
  end

  test "reconciliation runs cleanly with an indefinite license present" do
    open_sale!(@s1)
    pay!(order_for(@buyer, @s1))
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
