require "test_helper"

# Handoff 0100 -- the six dark pages (home, /about, /products, a guide, an episode, the dashboard) tell the browser
# they are dark: <meta name="color-scheme" content="dark"> in <head> and a dark, color-scheme:dark <body>. Every
# other page keeps the light body it always had and no declaration. Per page, not per controller.
class ColorSchemeTest < ActionDispatch::IntegrationTest
  DARK_BODY = %w[bg-page text-slate-900 antialiased [color-scheme:dark]].freeze
  LIGHT_BODY = %w[bg-slate-50 text-slate-900 antialiased].freeze

  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "cs-adm-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @member = User.create!(name: "회원", email: "cs-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    @line = ProductLine.create!(internal_name: "cs", customer_name: "색 가이드", slug: "cs-guide", summary: "요약", introduction: "소개", status: "published")
    @episode = @line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문", status: "published", open_preview: true)
    @line.content_episodes.create!(position: 2, customer_title: "둘째 편", body: "본문", status: "published")
    Commerce::ProductLineSales.set_price!(product_line: @line, total_amount: 0, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: @line.reload, actor: @admin)
  end

  def sign_in(user) = post(user_session_path, params: { user: { email: user.email, password: "password123" } })

  def assert_dark(path)
    get path
    assert_response :success, path
    assert_select "head meta[name='color-scheme'][content='dark']", 1, path
    assert_equal DARK_BODY, css_select("body").first["class"].split, path
  end

  def assert_light(path)
    get path
    assert_response :success, path
    assert_select "meta[name='color-scheme']", 0, path
    assert_equal LIGHT_BODY, css_select("body").first["class"].split, path
  end

  test "guest: the five dark pages a guest can open are declared dark" do
    [ root_path, about_path, products_path, product_line_path("cs-guide"), product_episode_path("cs-guide", "01") ].each do |path|
      assert_dark(path)
    end
  end

  test "guest: /dashboard lands on the sign-in page, which isn't declared" do
    get dashboard_path
    follow_redirect!
    assert_select "meta[name='color-scheme']", 0
    assert_equal LIGHT_BODY, css_select("body").first["class"].split
  end

  test "member: the dashboard and an episode with the comment form are dark; the light pages keep their body" do
    sign_in(@member)
    assert_light(product_continue_path("cs-guide")) # the confirm page (before use) is a guide address but a light page
    post claim_free_access_path(@line.product.code) # in use, so the episode page has the comment form
    assert_dark(dashboard_path)
    assert_dark(product_episode_path("cs-guide", "01"))
    assert_select "textarea[name='episode_comment[body]']" # the comment form is there (its own colors, see result.md)
    [ mypage_path, announcements_path, terms_path, privacy_path ].each { |path| assert_light(path) }
  end

  test "guest: sign-in, sign-up and notices keep the light body and no declaration" do
    [ new_user_session_path, new_user_registration_path, announcements_path ].each { |path| assert_light(path) }
  end

  test "admin: the admin screens and the guide / episode previews aren't declared; the customer pages still are" do
    sign_in(@admin)
    [ admin_dashboard_path, admin_product_lines_path, admin_product_line_path(@line), admin_content_episode_path(@episode),
      service_desk_path, refs_path ].each { |path| assert_light(path) }
    assert_dark(root_path)
    assert_dark(product_line_path("cs-guide"))
  end

  # Turbo Drive swaps <body> and merges <head>'s provisional elements (a meta without data-turbo-track) per visit, but
  # keeps <html>'s attributes (only lang / dir are synced) -- so nothing of this may sit on <html>.
  test "the declaration is only where Turbo swaps it per page: a plain head meta and the body" do
    get root_path
    meta = css_select("head meta[name='color-scheme']").first
    assert_nil meta["data-turbo-track"]
    assert_equal [], css_select("html").first.attributes.keys
    assert_no_match(/color-scheme/, css_select("html").first.to_html[0, 20])
  end
end
