require "test_helper"

# Handoff 0083 -- "browse" pages are dark, "read/handle" pages light: the home, the series list (/products, R1) and
# the series detail (/products/:slug, R2) use the dark header, the dark page and the display serif; notices, my page
# and the admin preview keep the light look and never load the font (the dashboard and the episode turned dark in
# 0084 -- see dark_frame_test.rb and dark_episode_test.rb). Only colors and fonts changed on the list -- its cards,
# badges and links are covered, unchanged, by product_line_list_test.rb.
class SeriesDarkThemeTest < ActionDispatch::IntegrationTest
  DARK_HEADER = "header.bg-page\\/90"
  LIGHT_HEADER = "header.bg-white\\/90"
  FONT = "link[rel='preload'][href*='Pretendard-Bold']"

  setup do
    @user = User.create!(name: "회원", email: "dt-#{SecureRandom.hex(3)}@example.com", password: "password123")
    @line = ProductLine.create!(internal_name: "다크", customer_name: "다크 시리즈", slug: "dark-line", introduction: "소개", status: "published")
    @line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문", status: "published")
  end

  def sign_in(user = @user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def assert_dark
    assert_select DARK_HEADER, 1
    assert_select FONT, 1
    assert_select "div.bg-page > #{DARK_HEADER}"
  end

  # D-010 (0084): a light-bodied customer page still has the dark frame (header, footer); only its body is light and
  # it doesn't load the display font. The admin area keeps the light header.
  def assert_light_body
    assert_select DARK_HEADER, 1
    assert_select LIGHT_HEADER, 0
    assert_select "div.bg-page > #{DARK_HEADER}", 0
    assert_select "link[rel='preload'][href*='Pretendard-Bold']", 0
  end

  test "the series list is dark like the home, titled 시리즈, with the display serif" do
    get products_path
    assert_response :success
    assert_dark
    assert_select "title", text: "가이드 | LEEDOX"
    assert_select "main h1.font-display", text: "가이드" # 0091 (D-011)
    assert_select "main a.bg-card[href=?]", product_line_path("dark-line")
    assert_not_includes css_select("main").first.to_html, "bg-white"
  end

  test "the home stays dark" do
    get root_path
    assert_dark
  end

  test "light-bodied pages keep their light body under the dark frame, without the font" do
    get announcements_path # was /pricing, removed in 0086
    assert_light_body

    sign_in
    get mypage_path
    assert_light_body
  end

  test "the mobile menu panel is dark on every customer page" do
    [ products_path, root_path, announcements_path ].each do |path| # /pricing removed in 0086
      get path
      assert_select "details[data-controller='mobile-menu'] div.bg-card", 1
      assert_select "details[data-controller='mobile-menu'] div.bg-white", 0
    end
  end

  test "signed in, the dark header and panel carry the member menu" do
    sign_in
    get products_path
    assert_dark
    assert_select "#{DARK_HEADER} a", text: "로그아웃"
    assert_select "details[data-controller='mobile-menu'] a.text-accent-ink", text: "로그아웃"
  end

  test "the list's filter tabs and state badges use the dark palette" do
    sign_in
    get products_path(filter: "free") # 0104: an empty tab shows only while it's the one you're on
    assert_select "nav[aria-label='가이드 필터'] a.bg-accent", text: /^무료/
    assert_select "nav[aria-label='가이드 필터'] a.bg-card", text: /^전체/
  end

  # --- R2: the series detail -------------------------------------------------------------------------

  def gate!(line, amount)
    Commerce::CatalogBootstrap.call!
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    admin = User.create!(name: "관리자", email: "dt-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    Commerce::ProductLineSales.set_price!(product_line: line, total_amount: amount, actor: admin)
    Commerce::ProductLineSales.start_sale!(product_line: line, actor: admin)
    line.reload
  end

  def box = css_select("#product-purchase").first

  test "the series detail is dark, titled with the series name, with the display serif and the footer" do
    @line.update!(summary: "한 줄 요약", introduction: "## 소제목\n\n본문 [링크](https://example.com) `코드`\n\n> 인용")
    @line.content_episodes.create!(position: 2, customer_title: "예정 편", body: "본문", status: "draft")
    get product_line_path("dark-line")
    assert_response :success
    assert_dark
    assert_select "title", text: "다크 시리즈 | LEEDOX"
    assert_select "main h1.font-display", text: "다크 시리즈"
    assert_select "a", text: "← 가이드 목록", count: 0 # 0094 A1: the back-to-list line is gone (the header has 가이드)
    assert_select "main .doc-content.doc-content-dark h2", text: "소제목"
    assert_select "main ol a.bg-card[data-turbo-prefetch='false'][href=?]", product_episode_path("dark-line", "01")
    assert_select "main ol div.opacity-70", 1
    assert_select "footer a[href=?]", announcements_path, text: "공지"
    assert_not_includes css_select("main").first.to_html, "text-gray-900"
  end

  test "purchase box, all four states, on the dark palette with the same content" do
    gate!(@line, 33_000)
    get product_line_path("dark-line")                     # for sale (guest)
    # 0093: dark-line has no image, so the box sits inside the header box, which carries the card color.
    assert_includes css_select("[data-guide-header]").first["class"], "bg-card"
    assert_includes box.text, "33,000원"
    assert_select "#product-purchase a.bg-accent", text: "구매하기"

    sign_in
    order = Commerce::OrderCreator.call!(user: @user, product_code: @line.product.code, offer_code: @line.lifetime_offer.code, requested_start_on: nil, provider: "manual")
    Commerce::ConfirmManualPayment.call!(order: order, actor: User.find_by!(role: :admin))
    get product_line_path("dark-line")                     # owned
    assert_equal "이용 중인 가이드입니다.", box.text.squish # 0092 R1
    assert_select "#product-purchase p.text-ink", minimum: 1

    free = ProductLine.create!(internal_name: "무료", customer_name: "무료 시리즈", slug: "dark-free", introduction: "소개", status: "published")
    gate!(free, 0)
    delete destroy_user_session_path
    get product_line_path("dark-free")                     # free start (guest)
    assert_select "#product-purchase a.bg-ok", text: "이용하기" # 0092 R1

    free.product.update!(sale_enabled: false)
    get product_line_path("dark-free")                     # unavailable
    assert_includes box.text, "현재 시작할 수 없습니다"
  ensure
    ENV.delete("LEEDOX_COMMERCE_ENABLED")
  end

  test "the admin preview of the same series stays light (same partials, no dark classes)" do
    @line.content_episodes.create!(position: 2, customer_title: "예정 편", body: "본문", status: "draft")
    admin = User.create!(name: "관리자", email: "dt-adm-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    sign_in(admin)
    get admin_product_line_path(@line)
    assert_response :success
    assert_select LIGHT_HEADER, 1 # the admin area keeps the light frame (D-010)
    assert_select DARK_HEADER, 0
    assert_select "link[rel='preload'][href*='Pretendard-Bold']", 0
    html = css_select("main").first.to_html
    assert_not_includes html, "doc-content-dark"
    assert_not_includes html, "#15181e"
    assert_not_includes html, "bg-card" # 0101: the dark card color is a token now
    assert_select "main h1.text-gray-900", text: "다크 시리즈"
    assert_select "main h2.text-slate-900", text: "에피소드"
    assert_select "main ol a.border-gray-200"
  end

  test "an episode body is dark with .doc-content-dark (0084 R2, D-010: series viewing)" do
    get product_episode_path("dark-line", "01")
    assert_dark
    assert_select "main .doc-content.doc-content-dark", minimum: 1
  end

  test "the series list's wording (0083 R2 d)" do
    sign_in
    get products_path(filter: "mine") # 0104: 내 가이드 0 shows only while it's the one you're on
    assert_no_match(/Guides/, css_select("main").text) # 0104: the label is gone (it was 0091's D-011 wording)
    assert_select "nav[aria-label='가이드 필터'] a", text: /\A내 가이드/
  end
end
