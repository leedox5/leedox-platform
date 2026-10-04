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
    assert_select "main section[aria-label*='AI, 오늘부터 시작']", count: 0
    doc = Nokogiri::HTML(response.body)
    assert_no_match(/aistart/i, doc.css("main").text)

    # Preparing product (aigravity) is NOT displayed on dashboard
    assert_select "main section[aria-label*='Antigravity']", count: 0
    assert_no_match(/aigravity/i, doc.css("main").text)

    # Handoff 0085 -- unowned paid earlier products (Chatdox, Claudox) no longer show either: 더 둘러보기 lists series.
    assert_no_match(/Chatdox|Claudox/, doc.css("main").text)
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

    # Chatdox (unowned) doesn't show (0085: 더 둘러보기 lists series, not earlier products)
    assert_no_match(/Chatdox/, doc.css("main").text)
  end

  # Handoff 0085 -- the separate "nothing to show" box (no earlier product on sale) is gone: with nothing in use the
  # member gets the one empty box, and with no series to browse either, it carries the 시리즈 둘러보기 link.
  test "3. Empty state UI is rendered when nothing is in use and there is no series to browse" do
    ProductOffer.update_all(active: false)

    get dashboard_path
    assert_response :success

    assert_select "section[aria-label='대시보드 안내']", 0
    assert_select "section[aria-label='이용 중인 콘텐츠 없음']" do
      assert_select "p", text: "아직 이용 중인 콘텐츠가 없습니다."
      assert_select "a[href=?]", products_path, text: "시리즈 둘러보기 →"
    end
    assert_select "section[aria-label='더 둘러보기']", 0
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
