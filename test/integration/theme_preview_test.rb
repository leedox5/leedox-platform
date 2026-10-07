require "test_helper"

# Handoff 0102 (D-014 step 2) -- the light values are previewed by whoever opens a page with ?theme=light: a cookie,
# then the same address without the parameter. Customer pages get data-theme="light" on <body> (the six dark pages
# also declare color-scheme light); the admin screens never do. Without the cookie nothing changes.
class ThemePreviewTest < ActionDispatch::IntegrationTest
  DARK_BODY = %w[bg-page text-slate-900 antialiased [color-scheme:dark]].freeze
  LIGHT_MODE_DARK_PAGE_BODY = %w[bg-page text-slate-900 antialiased [color-scheme:light]].freeze
  PLAIN_BODY = %w[bg-slate-50 text-slate-900 antialiased].freeze

  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "tp-adm-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @member = User.create!(name: "회원", email: "tp-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    @line = ProductLine.create!(internal_name: "tp", customer_name: "미리 보기 가이드", slug: "tp-guide", summary: "요약", introduction: "소개", status: "published")
    @episode = @line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문", status: "published", open_preview: true)
    Commerce::ProductLineSales.set_price!(product_line: @line, total_amount: 0, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: @line.reload, actor: @admin)
  end

  def sign_in(user) = post(user_session_path, params: { user: { email: user.email, password: "password123" } })
  def body = css_select("body").first
  def body_classes = body["class"].split
  def scheme_meta = css_select("head meta[name='color-scheme']").first&.[]("content")

  def assert_page(path, theme:, body_classes:, scheme:)
    get path
    assert_response :success, path
    theme.nil? ? assert_nil(body["data-theme"], path) : assert_equal(theme, body["data-theme"], path)
    assert_equal body_classes, self.body_classes, path
    scheme.nil? ? assert_nil(scheme_meta, path) : assert_equal(scheme, scheme_meta, path)
    assert_equal [], css_select("html").first.attributes.keys, "#{path}: nothing on <html>"
  end

  DARK_PAGES = -> { [ "/", "/about", "/products", "/products/tp-guide", "/products/tp-guide/01" ] }

  test "off (the default): every page is exactly as before -- no data-theme, the dark pages declare dark" do
    DARK_PAGES.call.each { |path| assert_page(path, theme: nil, body_classes: DARK_BODY, scheme: "dark") }
    [ new_user_session_path, announcements_path ].each { |path| assert_page(path, theme: nil, body_classes: PLAIN_BODY, scheme: nil) }
  end

  test "?theme=light sets the cookie and sends you on to the same address without the parameter, keeping the rest" do
    get products_path(filter: "free", theme: "light")
    assert_response :see_other
    assert_equal products_path(filter: "free"), URI(response.location).request_uri
    assert_equal "light", cookies[FrameThemeHelper::THEME_COOKIE]
    set_cookie = Array(response.headers["Set-Cookie"]).join("\n")
    assert_match(/leedox_theme=light/, set_cookie)
    assert_match(/expires=/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    get root_path(theme: "light")
    assert_redirected_to root_path
  end

  test "on: the six dark pages turn light and declare it; the light-bodied pages only get the attribute (their frame)" do
    get root_path(theme: "light")
    DARK_PAGES.call.each { |path| assert_page(path, theme: "light", body_classes: LIGHT_MODE_DARK_PAGE_BODY, scheme: "light") }
    [ new_user_session_path, new_user_registration_path, announcements_path, terms_path ].each do |path|
      assert_page(path, theme: "light", body_classes: PLAIN_BODY, scheme: nil)
    end
    sign_in(@member)
    assert_page(dashboard_path, theme: "light", body_classes: LIGHT_MODE_DARK_PAGE_BODY, scheme: "light")
    assert_page(mypage_path, theme: "light", body_classes: PLAIN_BODY, scheme: nil)
    assert_page(product_continue_path("tp-guide"), theme: "light", body_classes: PLAIN_BODY, scheme: nil)
  end

  test "on, admin: the admin screens and the guide / episode previews never get it; customer pages still do" do
    sign_in(@admin)
    get root_path(theme: "light")
    [ admin_product_lines_path, admin_product_line_path(@line), admin_content_episode_path(@episode), service_desk_path, refs_path ].each do |path|
      assert_page(path, theme: nil, body_classes: PLAIN_BODY, scheme: nil)
    end
    assert_page(root_path, theme: "light", body_classes: LIGHT_MODE_DARK_PAGE_BODY, scheme: "light")
  end

  test "?theme=dark turns it off; an unknown parameter is ignored; an unknown cookie value is the dark side" do
    get root_path(theme: "light")
    get root_path(theme: "dark")
    assert_redirected_to root_path
    assert_equal "dark", cookies[FrameThemeHelper::THEME_COOKIE]
    assert_page(root_path, theme: nil, body_classes: DARK_BODY, scheme: "dark")

    get root_path(theme: "blue")
    assert_response :success
    assert_equal "dark", cookies[FrameThemeHelper::THEME_COOKIE]

    cookies[FrameThemeHelper::THEME_COOKIE] = "sepia"
    assert_page(root_path, theme: nil, body_classes: DARK_BODY, scheme: "dark")
  end

  test "the light values are only in the CSS behind the attribute: the default page carries no light value" do
    get root_path
    assert_nil css_select("body").first["data-theme"]
    assert_no_match(/data-theme="/, response.body) # 0103: the switch's data-theme-toggle and its CSS variant are not the attribute
    assert_no_match(/f5f2ea/i, response.body)
  end
end
