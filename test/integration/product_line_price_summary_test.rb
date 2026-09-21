require "test_helper"

# Handoff 0059 -- price / access summary at the top of the ProductLine page.
# Display only: it reuses ProductSeason#acquirable? (the same "can a visitor get
# this now" rule the Season page's purchase box follows) and adds no button.
class ProductLinePriceSummaryTest < ActionDispatch::IntegrationTest
  ENV_KEYS = %w[LEEDOX_COMMERCE_ENABLED PAYMENT_PROVIDER PORTONE_API_SECRET PORTONE_STORE_ID PORTONE_CHANNEL_KEY
                PORTONE_KAKAOPAY_CHANNEL_KEY PORTONE_WEBHOOK_SECRET BANK_TRANSFER_ACCOUNT_INFO].freeze

  setup do
    Commerce::CatalogBootstrap.call!
    @previous_env = ENV_KEYS.to_h { |key| [ key, ENV[key] ] }
    ENV_KEYS.each { |key| ENV.delete(key) }
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    ENV["BANK_TRANSFER_ACCOUNT_INFO"] = "테스트은행 000-00-0000"

    @admin = User.create!(name: "관리자", email: "ps-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @buyer = User.create!(name: "구매자", email: "ps-buyer-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)

    @line = ProductLine.create!(internal_name: "A", customer_name: "제품 A", slug: "product-a", introduction: "소개", status: "published")
    @s1 = @line.product_seasons.create!(internal_name: "S01", customer_title: "첫 판", season_code: "S01", slug: "s01", status: "published", visibility: "public", position: 1)
    @ep1 = @s1.content_episodes.create!(position: 1, customer_title: "S01 첫 편", body: "# S01\n\nS01 유료 본문", status: "published")
  end

  teardown do
    @previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def open_sale!(season, amount)
    Commerce::SeasonSales.set_price!(season: season, total_amount: amount, actor: @admin)
    Commerce::SeasonSales.start_sale!(season: season, actor: @admin)
    season.reload
  end

  def add_season(code, status: "published", visibility: "public", position: 2)
    @line.product_seasons.create!(internal_name: code, customer_title: "#{code} 판", season_code: code, slug: code.downcase,
      status: status, visibility: visibility, position: position)
  end

  def summary_text
    css_select("#price-summary").text.squish
  end

  test "single free Season shows its code, 무료 and lifetime access to a guest" do
    open_sale!(@s1, 0)

    get product_line_path(@line.slug)
    assert_response :success
    assert_equal "가격 S01 · 무료 · 무기한 이용", summary_text
  end

  test "single priced Season shows the price in the Season page's own format" do
    open_sale!(@s1, 33_000)

    get product_line_path(@line.slug)
    assert_equal "가격 S01 · 33,000원 · 무기한 이용 (VAT 포함)", summary_text
  end

  test "the summary is information only: no buy or start button, Season card link unchanged" do
    open_sale!(@s1, 33_000)

    get product_line_path(@line.slug)
    assert_select "#price-summary a", count: 0
    assert_select "#price-summary button, #price-summary form", count: 0
    assert_select "a[href=?]", product_season_path(@line.slug, @s1.slug), text: /보러 가기/
  end

  test "several Seasons are summarised by the cheapest one currently for sale" do
    open_sale!(@s1, 33_000)
    s2 = add_season("S02")
    open_sale!(s2, 9_000)

    get product_line_path(@line.slug)
    assert_includes summary_text, "최저 9,000원 · S02 · 무기한 이용"
    assert_includes summary_text, "이용 가능한 Season 2개"
  end

  test "a Season whose sale was stopped is left out of the summary" do
    open_sale!(@s1, 33_000)
    s2 = add_season("S02")
    open_sale!(s2, 9_000)
    Commerce::SeasonSales.stop_sale!(season: s2, actor: @admin)

    get product_line_path(@line.slug)
    assert_equal "가격 S01 · 33,000원 · 무기한 이용 (VAT 포함)", summary_text
  end

  test "unlisted, draft and non-gated Seasons never contribute a price" do
    open_sale!(@s1, 33_000)
    unlisted = add_season("S02", visibility: "unlisted")
    open_sale!(unlisted, 1_000)
    reverted = add_season("S03")
    open_sale!(reverted, 2_000)
    reverted.update!(status: "draft") # sale was started, then the Season went back to draft
    add_season("S04") # published + public, but no commerce Product

    get product_line_path(@line.slug)
    assert_equal "가격 S01 · 33,000원 · 무기한 이용 (VAT 포함)", summary_text
  end

  test "no summary at all when nothing is on sale (stopped, never priced, or free-public only)" do
    get product_line_path(@line.slug) # S01 has no commerce Product
    assert_response :success
    assert_select "#price-summary", count: 0

    open_sale!(@s1, 33_000)
    Commerce::SeasonSales.stop_sale!(season: @s1, actor: @admin)
    get product_line_path(@line.slug)
    assert_response :success
    assert_select "#price-summary", count: 0
    assert_no_match(/오류|nil|NaN/, response.body.scan(%r{<main.*?</main>}m).join)
    assert_select "a[href=?]", product_season_path(@line.slug, @s1.slug), text: /보러 가기/
  end

  test "a signed-in visitor without a license sees the same summary as a guest" do
    open_sale!(@s1, 33_000)
    get product_line_path(@line.slug)
    guest_text = summary_text

    sign_in(@buyer)
    get product_line_path(@line.slug)
    assert_equal guest_text, summary_text
  end

  test "a license holder still sees the price summary and gains or loses no access because of it" do
    open_sale!(@s1, 33_000)
    order = Commerce::OrderCreator.call!(user: @buyer, product_code: @s1.product.code, offer_code: @s1.lifetime_offer.code, requested_start_on: nil, provider: "manual")
    Commerce::ConfirmManualPayment.call!(order: order, actor: @admin)
    other = User.create!(name: "다른사람", email: "ps-other-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)

    sign_in(@buyer)
    get product_line_path(@line.slug)
    assert_equal "가격 S01 · 33,000원 · 무기한 이용 (VAT 포함)", summary_text
    get product_season_episode_path(@line.slug, @s1.slug, @ep1.display_id)
    assert_response :success

    delete destroy_user_session_path
    sign_in(other)
    get product_line_path(@line.slug)
    assert_equal "가격 S01 · 33,000원 · 무기한 이용 (VAT 포함)", summary_text
    get product_season_episode_path(@line.slug, @s1.slug, @ep1.display_id)
    assert_redirected_to product_season_path(@line.slug, @s1.slug)
  end

  test "an unpublished product is still a 404 and the admin preview is unchanged" do
    open_sale!(@s1, 33_000)
    @line.update!(status: "draft")
    get product_line_path(@line.slug)
    assert_response :not_found

    sign_in(@admin)
    get admin_product_line_path(@line)
    assert_response :success
    assert_select "#price-summary", count: 0
  end
end
