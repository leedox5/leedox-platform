require "test_helper"

# Handoff 0103 (D-014 step 3) -- the dark / light switch in the customer header (PC menu: after the items, before
# 로그인 / the name; phones: left of ☰), the theme-color meta, and what never gets either (the admin screens).
class ThemeToggleTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "tt-adm-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @member = User.create!(name: "회원", email: "tt-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    @line = ProductLine.create!(internal_name: "tt", customer_name: "전환 가이드", slug: "tt-guide", summary: "요약", introduction: "소개", status: "published")
    @episode = @line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문", status: "published", open_preview: true)
    @line.content_episodes.create!(position: 2, customer_title: "예정 편", body: "본문", status: "draft")
    Commerce::ProductLineSales.set_price!(product_line: @line, total_amount: 0, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: @line.reload, actor: @admin)
  end

  def sign_in(user) = post(user_session_path, params: { user: { email: user.email, password: "password123" } })
  def toggles = css_select("header a[data-theme-toggle]")
  def theme_color = css_select("head meta[name='theme-color']").first&.[]("content")

  def assert_toggles(label:, href:, color:)
    assert_equal 2, toggles.size, "one in the PC menu, one in the phone header row"
    toggles.each do |toggle|
      assert_equal label, toggle["aria-label"]
      assert_equal label, toggle["title"]
      assert_equal href, toggle["href"]
      assert_equal "button", toggle["role"]
      assert_equal "theme-toggle", toggle["data-controller"]
      assert_equal "false", toggle["data-turbo-prefetch"]
      assert_equal "", toggle.text.strip, "an icon, no visible words"
      assert_equal %w[sun moon], toggle.css("svg").map { |svg| svg["data-theme-icon"] }
      %w[text-ink-2 hover:text-ink].each { |klass| assert_includes toggle["class"].split, klass }
    end
    assert_equal color, theme_color
  end

  test "guest: the switch in the PC menu before 로그인 and on the phone row left of ☰; dark by default" do
    get product_line_path("tt-guide")
    assert_toggles(label: "밝게 보기", href: "/products/tt-guide?theme=light", color: "#0e1014")
    pc = css_select("nav[aria-label='주요 내비게이션'] > a").map { |a| a["data-theme-toggle"] ? :switch : a.text.strip }
    assert_equal [ "가이드", "LEEDOX 소개", :switch, "로그인", "회원가입" ], pc
    phone = css_select("header > div > a[data-theme-toggle]").first
    assert_equal "details", phone.next_element.name
    %w[md:hidden h-10 w-10 ml-auto].each { |klass| assert_includes phone["class"].split, klass }
    %w[h-9 w-9].each { |klass| assert_includes toggles.first["class"].split, klass }
    sun, moon = toggles.first.css("svg")
    assert_includes sun["class"].split, "[[data-theme=light]_&]:hidden"
    assert_includes moon["class"].split, "hidden"
    assert_includes moon["class"].split, "[[data-theme=light]_&]:block"
  end

  test "the name, the link and theme-color follow the cookie; other query parameters stay on the link" do
    cookies[FrameThemeHelper::THEME_COOKIE] = "light"
    get products_path(filter: "free")
    assert_toggles(label: "어둡게 보기", href: "/products?filter=free&theme=dark", color: "#f5f2ea")
    cookies[FrameThemeHelper::THEME_COOKIE] = "dark"
    get products_path
    assert_toggles(label: "밝게 보기", href: "/products?theme=light", color: "#0e1014")
    cookies[FrameThemeHelper::THEME_COOKIE] = "sepia"
    get root_path
    assert_toggles(label: "밝게 보기", href: "/?theme=light", color: "#0e1014")
  end

  test "member: before the name and 로그아웃; on a light-bodied page (마이페이지) too" do
    sign_in(@member)
    get dashboard_path
    pc = css_select("nav[aria-label='주요 내비게이션'] > *").map { |n| n["data-theme-toggle"] ? :switch : n.text.strip }
    assert_equal [ "가이드", "LEEDOX 소개", "대시보드", "마이페이지", :switch, "회원", "로그아웃" ], pc
    get mypage_path
    assert_toggles(label: "밝게 보기", href: "/mypage?theme=light", color: "#0e1014")
  end

  test "admin: the switch on customer pages, never on the admin screens -- neither theme-color, even with light chosen" do
    sign_in(@admin)
    cookies[FrameThemeHelper::THEME_COOKIE] = "light"
    get root_path
    assert_toggles(label: "어둡게 보기", href: "/?theme=dark", color: "#f5f2ea")
    [ admin_product_lines_path, admin_product_line_path(@line), admin_content_episode_path(@episode), service_desk_path, refs_path ].each do |path|
      get path
      assert_response :success
      assert_empty toggles, path
      assert_nil theme_color, path
      assert_select "[data-theme-toggle]", 0
    end
  end

  test "a prefetch of the switch's link never switches the mode" do
    get root_path(theme: "light"), headers: { "X-Sec-Purpose" => "prefetch" }
    assert_response :success
    assert_nil cookies[FrameThemeHelper::THEME_COOKIE]
    get root_path(theme: "light"), headers: { "Sec-Purpose" => "prefetch;prerender" }
    assert_nil cookies[FrameThemeHelper::THEME_COOKIE]
    get root_path(theme: "light")
    assert_equal "light", cookies[FrameThemeHelper::THEME_COOKIE]
  end

  # The script switches in place; it must write what the server reads and show what the server would draw.
  test "the script and the server agree on the cookie, the names and the colors" do
    js = File.read(Rails.root.join("app/javascript/controllers/theme_toggle_controller.js"))
    assert_includes js, %(const COOKIE = "#{FrameThemeHelper::THEME_COOKIE}")
    FrameThemeHelper::THEME_TOGGLE_LABELS.each { |theme, label| assert_includes js, %(#{theme}: "#{label}") }
    FrameThemeHelper::THEME_COLORS.each { |theme, color| assert_includes js, %(#{theme}: "#{color}") }
    assert_includes js, "max-age=31536000; samesite=lax"
    assert_includes js, %(dark: "[color-scheme:dark]", light: "[color-scheme:light]")
    assert_includes FrameThemeHelper::BODY_CLASS.values.join(" "), "[color-scheme:light]"
    assert_includes js, "Turbo?.cache?.clear?.()"
    assert_includes js, 'addEventListener("pageshow"'
  end

  test "the 공개 예정 card: 70% on the dark side as before, 80% on the light side" do
    get product_line_path("tt-guide")
    card = css_select("#episodes + ol > li > div").first
    assert_includes card["class"].split, "opacity-70"
    assert_includes card["class"].split, "[[data-theme=light]_&]:opacity-80"
    assert_not_includes card["class"].split, "opacity-80"
  end
end
