require "test_helper"

# Handoff 0065 -- a ProductLine is the sellable unit: it carries the commerce
# Product (price, sale switch, license) that used to hang off a Season, and its
# own public reach (visibility) and optional series relation.
class ProductLineSellingTest < ActiveSupport::TestCase
  ENV_KEYS = %w[LEEDOX_COMMERCE_ENABLED PAYMENT_PROVIDER PORTONE_API_SECRET PORTONE_STORE_ID PORTONE_CHANNEL_KEY PORTONE_KAKAOPAY_CHANNEL_KEY BANK_TRANSFER_ACCOUNT_INFO].freeze

  setup do
    Commerce::CatalogBootstrap.call!
    @previous_env = ENV_KEYS.to_h { |key| [ key, ENV[key] ] }
    ENV_KEYS.each { |key| ENV.delete(key) }
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    ENV["BANK_TRANSFER_ACCOUNT_INFO"] = "테스트은행 000-00-0000"
    @admin = User.create!(name: "관리자", email: "sell-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @line = ProductLine.create!(internal_name: "A", customer_name: "제품 A", slug: "sell-a", introduction: "소개", status: "published")
  end

  teardown do
    @previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def price!(amount, line: @line)
    Commerce::ProductLineSales.set_price!(product_line: line, total_amount: amount, actor: @admin)
    line.reload
  end

  def open_sale!(amount, line: @line)
    price!(amount, line: line)
    Commerce::ProductLineSales.start_sale!(product_line: line, actor: @admin)
    line.reload
  end

  # --- visibility and reach --------------------------------------------------

  test "visibility defaults to public and is validated" do
    assert_equal "public", @line.visibility
    @line.visibility = "secret"
    assert_not @line.valid?
    assert_includes @line.errors.attribute_names, :visibility
  end

  test "reachable means published and not private (unlisted is reachable by URL)" do
    private_line = ProductLine.create!(internal_name: "p", customer_name: "p", slug: "sell-private", introduction: "p", status: "published", visibility: "private")
    unlisted = ProductLine.create!(internal_name: "u", customer_name: "u", slug: "sell-unlisted", introduction: "u", status: "published", visibility: "unlisted")
    draft = ProductLine.create!(internal_name: "d", customer_name: "d", slug: "sell-draft", introduction: "d", visibility: "public")

    assert_equal [ @line, unlisted ].sort_by(&:id), ProductLine.customer_reachable.to_a.sort_by(&:id)
    assert @line.customer_reachable?
    assert_not private_line.customer_reachable?
    assert_not draft.customer_reachable?
  end

  # --- series ----------------------------------------------------------------

  test "the series relation is optional, normalized and validated" do
    assert_nil @line.series_key
    @line.update!(series_key: "  Was-Core ", series_label: " 시즌1 ", series_position: 2)
    assert_equal [ "was-core", "시즌1", 2 ], [ @line.series_key, @line.series_label, @line.series_position ]

    @line.series_key = "Not A Key!"
    assert_not @line.valid?
    @line.series_key = ""
    assert @line.valid?
    assert_nil @line.series_key, "blank means stand-alone"
    @line.series_position = -1
    assert_not @line.valid?
  end

  test "series members are the lines sharing the key, in order" do
    second = ProductLine.create!(internal_name: "b", customer_name: "b", slug: "sell-b", introduction: "b", series_key: "grp", series_position: 2)
    first = ProductLine.create!(internal_name: "c", customer_name: "c", slug: "sell-c", introduction: "c", series_key: "grp", series_position: 1)
    ProductLine.create!(internal_name: "o", customer_name: "o", slug: "sell-o", introduction: "o", series_key: "other")

    assert_equal [ first, second ], first.series_members.to_a
    assert_empty @line.series_members
  end

  # --- selling ---------------------------------------------------------------

  test "a line without a commerce Product is free and public, and not acquirable" do
    assert_not @line.gated?
    assert_nil @line.lifetime_offer
    assert_nil @line.price
    assert_not @line.free?
    assert_not @line.for_sale?
    assert_not @line.acquirable?
  end

  test "setting a price creates the Product for the line (1:1) with the line's URL and name; sales start stopped" do
    price!(33_000)
    product = @line.product

    assert @line.gated?
    assert_equal @line, product.product_line
    assert product.line_product?
    assert_equal "sell_a", product.code
    assert_equal "제품 A", product.name
    assert_equal "/products/sell-a", product.landing_page_path
    assert_not product.sale_enabled?
    assert_equal 33_000, @line.price
    assert_not @line.for_sale?
  end

  test "a paid line is for sale once the sale is started (and commerce is on); a free one is free-start-open instead" do
    open_sale!(33_000)
    assert @line.for_sale?
    assert @line.acquirable?
    assert_not @line.free_start_open?

    free = ProductLine.create!(internal_name: "f", customer_name: "f", slug: "sell-free", introduction: "f", status: "published")
    open_sale!(0, line: free)
    assert free.free?
    assert free.free_start_open?
    assert free.acquirable?
    assert_not free.for_sale?
  end

  test "a free start does not need the global commerce switch, a paid sale does" do
    open_sale!(33_000)
    free = ProductLine.create!(internal_name: "f", customer_name: "f", slug: "sell-free", introduction: "f", status: "published")
    open_sale!(0, line: free)
    ENV["LEEDOX_COMMERCE_ENABLED"] = "false"

    assert_not @line.reload.for_sale?
    assert free.reload.free_start_open?
  end

  test "an unpublished or private line cannot start a sale, and a stopped sale is not acquirable" do
    price!(33_000)
    @line.update!(status: "draft")
    assert_raises(Commerce::ProductLineSales::Invalid) { Commerce::ProductLineSales.start_sale!(product_line: @line, actor: @admin) }
    @line.update!(status: "published", visibility: "private")
    assert_raises(Commerce::ProductLineSales::Invalid) { Commerce::ProductLineSales.start_sale!(product_line: @line, actor: @admin) }

    @line.update!(visibility: "public")
    open_sale!(33_000)
    Commerce::ProductLineSales.stop_sale!(product_line: @line, actor: @admin)
    assert_not @line.reload.acquirable?
  end

  test "a free start is closed once the line stops being reachable" do
    open_sale!(0)
    assert @line.free_start_open?
    @line.update!(visibility: "private")
    assert_not @line.free_start_open?
  end

  test "the Product cannot be removed while a line holds it, and only line products get one-time offers" do
    price!(33_000)
    assert_not @line.product.destroy

    stray = Product.create!(code: "stray_product", name: "stray", active: true)
    offer = ProductOffer.new(product: stray, code: "stray-once", duration_months: nil, currency: "KRW", active: true, discount_bps: 0,
      supply_amount: 30_000, vat_amount: 3_000, total_amount: 33_000, version: 1)
    assert_not offer.valid?, "a Product with no line may not have a one-time offer"
  end

  test "non-admins cannot change prices or sales" do
    buyer = User.create!(name: "일반", email: "sell-user-#{SecureRandom.hex(3)}@example.com", password: "password123")
    assert_raises(Pundit::NotAuthorizedError) { Commerce::ProductLineSales.set_price!(product_line: @line, total_amount: 1000, actor: buyer) }
  end
end
