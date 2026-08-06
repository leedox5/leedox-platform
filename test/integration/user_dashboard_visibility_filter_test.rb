require "test_helper"

class UserDashboardVisibilityFilterTest < ActionDispatch::IntegrationTest
  KST = ActiveSupport::TimeZone["Asia/Seoul"]

  setup do
    Commerce::CatalogBootstrap.call!
    @user = User.create!(name: "대시보드 유저", email: "dashboard-visibility@example.com", password: "password123")
    login_as(@user)
  end

  test "1. Free access product (aistart) and preparing product (aigravity) are excluded from user dashboard cards (Option B)" do
    get dashboard_path
    assert_response :success

    # Free access product (aistart) is NOT displayed on dashboard
    assert_select "section[aria-label*='AI, 오늘부터 시작']", count: 0
    assert_no_match(/aistart/i, response.body)

    # Preparing product (aigravity) is NOT displayed on dashboard
    assert_select "section[aria-label*='Antigravity']", count: 0
    assert_no_match(/aigravity/i, response.body)

    # Bottom catalog grid displays purchasable paid products (Chatdox, Claudox) for unowned user
    assert_select "section[aria-label='전체 카탈로그 둘러보기']" do
      assert_select "h3", text: "Chatdox"
      assert_select "h3", text: "Claudox"
    end
  end

  test "2. Licensed/active paid product is placed in main section, unowned product is in bottom catalog section" do
    claudox = Product.find_by!(code: "claudox")
    today = Date.current
    last_usable = today + 30.days
    access_ends = KST.local((last_usable + 1.day).year, (last_usable + 1.day).month, (last_usable + 1.day).day)

    License.create!(
      user: @user,
      product: claudox,
      source: "paid",
      status: "active",
      starts_on: today,
      last_usable_on: last_usable,
      access_ends_at: access_ends
    )

    get dashboard_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)

    # Claudox (owned) appears in main section
    main_section = doc.at_css("section[aria-label='Claudox 현황']")
    assert main_section, "Claudox must appear in main section"
    assert_includes main_section.text, "Claudox"

    # Chatdox (unowned) appears in bottom catalog grid section
    catalog_section = doc.at_css("section[aria-label='전체 카탈로그 둘러보기']")
    assert catalog_section, "Chatdox must appear in bottom catalog section"
    assert_includes catalog_section.text, "Chatdox"
  end

  test "3. Empty state UI is rendered when 0 dashboard products are available" do
    # Temporarily deactivate offers to simulate 0 active paid products
    ProductOffer.update_all(active: false)

    get dashboard_path
    assert_response :success

    assert_select "section[aria-label='대시보드 안내']" do
      assert_select "p", text: "현재 대시보드에 표시할 상품이 없습니다."
    end
  end

  test "4. Scope is restricted to user dashboard cards -- pricing page and admin page remain untouched" do
    # Pricing page still displays aistart (free product) and preparing products
    get pricing_path
    assert_response :success
    assert_select "h2", text: /AI, 오늘부터 시작/

    # Admin user management still includes all products in subscription column logic
    admin = User.create!(name: "관리자", email: "admin-visibility@example.com", password: "password123", role: :admin)
    login_as(admin)
    get admin_users_path
    assert_response :success
    assert_select "table"
  end

  private

  def login_as(user)
    delete destroy_user_session_path rescue nil
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
