require "test_helper"

class PricingSummaryPageTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @previous_flag = ENV["LEEDOX_COMMERCE_ENABLED"]
    @chatdox = Product.find_by!(code: "chatdox")
    @claudox = Product.find_by!(code: "claudox")
  end

  teardown do
    @previous_flag.nil? ? ENV.delete("LEEDOX_COMMERCE_ENABLED") : ENV["LEEDOX_COMMERCE_ENABLED"] = @previous_flag
  end

  test "shows a card per product with the correct lowest price, sale status, tagline, and detail link" do
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    @chatdox.update!(sale_enabled: true)
    @claudox.update!(sale_enabled: false)

    get pricing_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    cards = doc.css("article")
    assert_equal 2, cards.size

    chatdox_card = cards.find { |card| card.text.include?("Chatdox") }
    assert chatdox_card, "expected a Chatdox card"
    assert_match(/판매 중/, chatdox_card.text)
    assert_match(/최저 7,700원부터/, chatdox_card.text)
    assert_match(@chatdox.tagline, chatdox_card.text)
    detail_link = chatdox_card.at_css("a")
    assert_equal chatdox_path, detail_link["href"]
    assert_equal "자세히 보기", detail_link.text

    claudox_card = cards.find { |card| card.text.include?("Claudox") }
    assert claudox_card, "expected a Claudox card"
    assert_match(/준비 중/, claudox_card.text)
    assert_match(/최저 3,850원부터/, claudox_card.text)
    assert_equal claudox_path, claudox_card.at_css("a")["href"]
  end

  test "a product with no offers shows a graceful placeholder instead of crashing" do
    @claudox.product_offers.destroy_all

    get pricing_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    claudox_card = doc.css("article").find { |card| card.text.include?("Claudox") }
    assert_match(/가격 준비 중/, claudox_card.text)
  end

  test "a brand-new product with no tagline/detail-page mapping still gets a card automatically" do
    widget = Product.create!(code: "widget_test", name: "Widget Test", active: true, sale_enabled: false)
    assert_nil widget.tagline
    assert_nil widget.landing_page_path

    get pricing_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    cards = doc.css("article")
    assert_equal 3, cards.size
    widget_card = cards.find { |card| card.text.include?("Widget Test") }
    assert widget_card, "expected the newly seeded product to get a card without any code changes"
    assert_match(/가격 준비 중/, widget_card.text) # no offers yet
    assert_nil widget_card.at_css("a"), "no detail page exists for it yet, so there should be no dangling link"
  end

  test "top navigation shows a single 가격 link instead of per-product links, for guests, signed-in users, and admins" do
    get root_path
    assert_response :success
    assert_select "header nav[aria-label='주요 내비게이션'] a[href=?]", pricing_path, text: "가격"
    assert_select "nav[aria-label='모바일 내비게이션'] a[href=?]", pricing_path, text: "가격"
    assert_select "header nav[aria-label='주요 내비게이션'] a", text: "Chatdox", count: 0
    assert_select "header nav[aria-label='주요 내비게이션'] a", text: "Claudox", count: 0

    user = User.create!(name: "테스트 유저", email: "pricing-nav-user@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    get root_path
    assert_response :success
    assert_select "header nav[aria-label='주요 내비게이션'] a[href=?]", pricing_path, text: "가격"
    assert_select "header nav[aria-label='주요 내비게이션'] a", text: "Chatdox", count: 0
    assert_select "header nav[aria-label='주요 내비게이션'] a", text: "Claudox", count: 0

    admin = User.create!(name: "테스트 유저", email: "pricing-nav-admin@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }
    get root_path
    assert_response :success
    assert_select "header nav[aria-label='주요 내비게이션'] a[href=?]", pricing_path, text: "가격"
    assert_select "header nav[aria-label='주요 내비게이션'] a", text: "Chatdox", count: 0
    assert_select "header nav[aria-label='주요 내비게이션'] a", text: "Claudox", count: 0
  end

  test "/chatdox and /claudox pages themselves are unchanged and still directly reachable" do
    get chatdox_path
    assert_response :success

    get claudox_path
    assert_response :success
  end
end
