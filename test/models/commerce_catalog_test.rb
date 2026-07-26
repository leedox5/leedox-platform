require "test_helper"

class CommerceCatalogTest < ActiveSupport::TestCase
  setup do
    Commerce::CatalogBootstrap.call!
  end

  test "catalog separates products and installs exact Chatdox and Claudox offers" do
    chatdox = Product.find_by!(code: "chatdox")
    claudox = Product.find_by!(code: "claudox")

    # aistart is a free, offer-less product (see leedox_multi_product_platform_stage5_r1) --
    # present in the catalog but deliberately outside this test's Chatdox/Claudox offer assertions.
    assert_equal [ "aistart", "chatdox", "claudox" ], Product.order(:code).pluck(:code)
    assert_equal false, claudox.sale_enabled?
    assert_equal [
      [ "chatdox-1m-v1", 1, 7_000, 700, 7_700, 0 ],
      [ "chatdox-3m-v1", 3, 21_000, 2_100, 23_100, 0 ],
      [ "chatdox-6m-v1", 6, 37_800, 3_780, 41_580, 1_000 ],
      [ "chatdox-12m-v1", 12, 67_200, 6_720, 73_920, 2_000 ]
    ], chatdox.product_offers.ordered.pluck(
      :code, :duration_months, :supply_amount, :vat_amount, :total_amount, :discount_bps
    )

    # Claudox pricing is exactly 50% of the matching Chatdox offer, discount_bps tiers unchanged.
    assert_equal chatdox.product_offers.ordered.pluck(:duration_months, :discount_bps),
      claudox.product_offers.ordered.pluck(:duration_months, :discount_bps)
    assert_equal [
      [ "claudox-1m-v1", 1, 3_500, 350, 3_850, 0 ],
      [ "claudox-3m-v1", 3, 10_500, 1_050, 11_550, 0 ],
      [ "claudox-6m-v1", 6, 18_900, 1_890, 20_790, 1_000 ],
      [ "claudox-12m-v1", 12, 33_600, 3_360, 36_960, 2_000 ]
    ], claudox.product_offers.ordered.pluck(
      :code, :duration_months, :supply_amount, :vat_amount, :total_amount, :discount_bps
    )
  end

  test "aistart is registered as a permanently offer-less, not-for-sale product" do
    aistart = Product.find_by!(code: "aistart")

    assert aistart.active?
    assert_not aistart.sale_enabled?
    assert_empty aistart.product_offers
  end

  test "catalog bootstrap is idempotent and does not overwrite operator changes" do
    offer = ProductOffer.find_by!(code: "chatdox-1m-v1")
    offer.update!(active: false)

    assert_no_difference [ "Product.count", "ProductOffer.count" ] do
      2.times { Commerce::CatalogBootstrap.call! }
    end

    assert_not offer.reload.active?
  end

  test "catalog database and model constraints reject duplicates and invalid totals" do
    chatdox = Product.find_by!(code: "chatdox")
    duplicate = Product.new(code: chatdox.code, name: "Duplicate")
    assert_not duplicate.valid?

    offer = ProductOffer.new(
      product: chatdox,
      code: "invalid-total",
      version: 2,
      duration_months: 1,
      supply_amount: 100,
      vat_amount: 10,
      total_amount: 999,
      discount_bps: 0,
      currency: "KRW"
    )
    assert_not offer.valid?
    assert_includes offer.errors[:total_amount], "must equal supply amount plus VAT"
  end

  test "payment transaction requires a purchase order" do
    transaction = PaymentTransaction.new(
      provider: "portone",
      provider_payment_id: "no-order-payment",
      order_id: "no-order",
      status: "active",
      amount: 9_900,
      currency: "KRW",
      provider_payload: {}
    )

    assert_not transaction.valid?
    assert_includes transaction.errors[:purchase_order], "must exist"
  end
end
