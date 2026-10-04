require "test_helper"

# Handoff 0084 R1 (D-010) -- the frame (header, mobile menu panel, footer) is dark on every customer page; the admin
# area (/admin/...) and the screens only admins use (service desk, refs -- R2) keep the light header. The dashboard body is dark like the home and the series pages; pages for
# input, payment and documents keep their light body. Colors only -- content is covered by the existing tests.
class DarkFrameTest < ActionDispatch::IntegrationTest
  DARK_HEADER = "header.bg-\\[\\#0e1014\\]\\/90"
  LIGHT_HEADER = "header.bg-white\\/90"
  DARK_PANEL = "details[data-controller='mobile-menu'] div.bg-\\[\\#15181e\\]"
  DARK_FOOTER = "footer.bg-\\[\\#0e1014\\]"

  setup do
    Commerce::CatalogBootstrap.call!
    @user = User.create!(name: "회원", email: "df-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    @admin = User.create!(name: "관리자", email: "df-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @line = ProductLine.create!(internal_name: "틀", customer_name: "틀 시리즈", slug: "frame-line", introduction: "소개", status: "published")
    @line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문", status: "published")
    Announcement.create!(title: "공지", body: "본문", published: true)
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def assert_dark_frame(path)
    get path
    assert_response :success, path
    assert_select DARK_HEADER, 1, "#{path}: dark header"
    assert_select LIGHT_HEADER, 0, "#{path}: no light header"
    assert_select DARK_PANEL, 1, "#{path}: dark mobile panel"
    assert_operator css_select("footer").size, :<=, 1, "#{path}: at most one footer"
    assert_select "footer:not(.bg-\\[\\#0e1014\\])", 0, "#{path}: a footer, if any, is dark"
  end

  GUEST_PAGES = %i[root_path products_path pricing_path announcements_path terms_path privacy_path new_user_session_path
                   new_user_registration_path new_user_password_path].freeze

  test "guests get the dark frame on every customer page, light-bodied ones included" do
    GUEST_PAGES.each { |page| assert_dark_frame(send(page)) }
    assert_dark_frame(product_line_path("frame-line"))
    assert_dark_frame(product_episode_path("frame-line", "01"))
    assert_dark_frame(announcement_path(Announcement.last))
    assert_dark_frame("/chatdox")
    assert_dark_frame("/content/aistart")
  end

  test "members get the dark frame too, with their menu in it" do
    sign_in(@user)
    [ root_path, products_path, pricing_path, dashboard_path, mypage_path, edit_user_registration_path,
      announcements_path, product_episode_path("frame-line", "01") ].each { |path| assert_dark_frame(path) }
    get mypage_path
    assert_select "#{DARK_HEADER} a", text: "로그아웃"
  end

  test "the footer is dark wherever it appears, with the same links" do
    [ root_path, products_path, pricing_path, announcements_path ].each do |path|
      get path
      assert_select DARK_FOOTER, 1
      links = css_select("footer a").map { |a| a.text.strip }
      assert_equal [ "공지", "이용 약관", "개인정보 처리 방침", "사업자정보확인" ], links
    end
  end

  test "an admin sees the dark frame on customer pages and the light header in /admin" do
    sign_in(@admin)
    assert_dark_frame(products_path)
    assert_dark_frame(dashboard_path)
    [ admin_dashboard_path, admin_product_lines_path, admin_product_line_path(@line), admin_episode_comments_path,
      admin_announcements_path ].each do |path|
      get path
      assert_response :success, path
      assert_select LIGHT_HEADER, 1, "#{path}: admin keeps the light header"
      assert_select DARK_HEADER, 0
    end
  end

  test "the admin-only screens outside /admin (service desk, refs) keep the light header (R2)" do
    sign_in(@admin)
    [ service_desk_path, new_service_desk_request_path, refs_path ].each do |path|
      get path
      assert_response :success, path
      assert_select LIGHT_HEADER, 1, "#{path}: admin-only screen keeps the light header"
      assert_select DARK_HEADER, 0, path
      assert_select "details[data-controller='mobile-menu'] div.bg-white", 1, "#{path}: light mobile panel"
    end
  end

  test "the dashboard body is dark, with the display font and dark cards" do
    sign_in(@user)
    get dashboard_path
    assert_select "div.bg-\\[\\#0e1014\\] > #{DARK_HEADER}"
    assert_select "link[href*='fonts.googleapis.com'][href*='Gowun+Batang']", 1
    assert_select "main h1.font-display", text: /안녕하세요/
    assert_not_includes css_select("main").first.to_html, "bg-white "
  end

  test "dashboard cards and badges use the dark palette, keeping their meaning colors" do
    license = ->(product, starts, last) { License.create!(user: @user, product: product, source: "paid", status: "active", starts_on: starts, last_usable_on: last, access_ends_at: Time.zone.local((last + 1).year, (last + 1).month, (last + 1).day)) }
    gate = ProductLine.create!(internal_name: "g", customer_name: "이용 시리즈", slug: "frame-in-use", introduction: "소개", status: "published")
    gate.update!(product: Product.create!(code: "frame_in_use", name: "이용 시리즈"))
    License.create!(user: @user, product: gate.product, source: "free", status: "active", starts_on: Date.current, last_usable_on: nil, access_ends_at: nil)
    license.call(Product.find_by!(code: "chatdox"), Date.current - 5, Date.current + 25)
    license.call(Product.find_by!(code: "claudox"), Date.current - 40, Date.current - 10)
    sign_in(@user)
    get dashboard_path

    assert_select "[data-series-card='frame-in-use'].bg-\\[\\#15181e\\]"
    assert_select "[data-series-card='frame-in-use'] span.text-\\[\\#7dd3a8\\]", text: "이용 중"
    assert_select "section[aria-label='Chatdox 현황'].bg-\\[\\#15181e\\] span.text-\\[\\#7dd3a8\\]", text: "이용 중"
    assert_select "section[aria-label='Chatdox 현황'] [role=progressbar] div.bg-\\[\\#f0a53c\\]"
    # 0085: 더 둘러보기 holds series (the dark /products card; frame-line isn't in use), no 만료 earlier product.
    assert_select "section[aria-label='더 둘러보기'] a.bg-\\[\\#15181e\\][href=?]", product_line_path("frame-line")
    assert_not_includes css_select("main").text, "Claudox"
  end

  test "light-bodied pages keep their light body and don't load the display font" do
    sign_in(@user)
    [ mypage_path, pricing_path, announcements_path, edit_user_registration_path ].each do |path|
      get path
      assert_select "div.bg-\\[\\#0e1014\\] > header", 0, "#{path}: body stays light"
      assert_select "link[href*='fonts.googleapis.com']", 0, path
    end
  end
end
