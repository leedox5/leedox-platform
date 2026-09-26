require "test_helper"

# Handoff 0071 R1 (b, c) -- the story-series home: the featured series hero and the per-track rows. Every rule is
# an existing one (ProductLine.listed, access_state/owned_by?, the 0070 published / 공개 예정 split).
class StorySeriesHomeTest < ActionDispatch::IntegrationTest
  ENV_KEYS = %w[LEEDOX_COMMERCE_ENABLED PAYMENT_PROVIDER PORTONE_API_SECRET PORTONE_STORE_ID PORTONE_CHANNEL_KEY
                PORTONE_KAKAOPAY_CHANNEL_KEY PORTONE_WEBHOOK_SECRET BANK_TRANSFER_ACCOUNT_INFO].freeze

  setup do
    Commerce::CatalogBootstrap.call!
    @previous_env = ENV_KEYS.to_h { |key| [ key, ENV[key] ] }
    ENV_KEYS.each { |key| ENV.delete(key) }
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    @admin = User.create!(name: "관리자", email: "home-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
  end

  teardown { @previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value } }

  def sign_in(user) = post(user_session_path, params: { user: { email: user.email, password: "password123" } })

  def series(slug, **attrs)
    ProductLine.create!({ internal_name: slug, customer_name: "시리즈 #{slug}", slug: slug, introduction: "소개", status: "published" }.merge(attrs))
  end

  def episodes(line, published:, drafts: [])
    published.each { |p| line.content_episodes.create!(position: p, customer_title: "공개 #{p}", status: "published") }
    drafts.each { |p| line.content_episodes.create!(position: p, customer_title: "예정 #{p}", status: "draft") }
  end

  def open_sale!(line, amount)
    Commerce::ProductLineSales.set_price!(product_line: line, total_amount: amount, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: line, actor: @admin)
    line.reload
  end

  def hero = css_select("section[aria-labelledby='featured-series-title']").first

  # --- b. hero ------------------------------------------------------------------

  test "no featured series -- no hero at all (never an empty one)" do
    series("no-hero", track: "basics")
    get root_path
    assert_response :success
    assert_nil hero
  end

  test "a featured series that isn't listed never shows as the hero" do
    series("draft-hero", featured: true, status: "draft")
    series("private-hero-x") # not featured
    get root_path
    assert_nil hero
  end

  test "the featured series: label, name, summary, release line, both buttons and the cover slot" do
    git = series("git-core", featured: true, summary: "변경 이력을 남기는 법부터")
    episodes(git, published: [ 1, 2 ], drafts: [ 3, 4, 5 ])
    open_sale!(git, 0)

    get root_path
    assert hero, "hero rendered"
    text = hero.text
    assert_includes text, "지금 시작하는 시리즈 · S01 · 5편 · 무료"
    assert_equal "시리즈 git-core", hero.at_css("h1").text.strip
    assert_includes text, "변경 이력을 남기는 법부터"
    assert_includes text, "E01·E02 공개 · E03~E05 공개 예정"
    assert hero.at_css("a[href='#{product_episode_path(git.slug, '01')}']")&.text&.include?("E01부터 보기")
    assert hero.at_css("a[href='#{product_line_path(git.slug)}']")&.text&.include?("시리즈 소개")
    assert hero.at_css("div[aria-hidden='true'].aspect-video"), "no cover -- the placeholder takes its place"
  end

  test "with nothing coming up the release line is just the published count; with nothing published only 시리즈 소개 remains" do
    done = series("done-line", featured: true)
    episodes(done, published: [ 1, 2 ])
    get root_path
    assert_includes hero.text, "공개 2편"

    fresh = series("fresh-line")
    episodes(fresh, published: [], drafts: [ 1 ])
    fresh.update!(featured: true)
    get root_path
    assert_includes hero.text, "E01 공개 예정"
    assert_nil hero.at_css("a[href^='#{product_line_path(fresh.slug)}/']"), "no episode to start from"
    assert hero.at_css("a[href='#{product_line_path(fresh.slug)}']")
  end

  test "the hero's price label follows access_state: a price, then 이용 중 for someone who owns it" do
    paid = series("paid-hero", featured: true)
    episodes(paid, published: [ 1 ])
    open_sale!(paid, 19_000)
    get root_path
    assert_includes hero.text, "19,000원"

    free = series("free-hero", featured: true)
    episodes(free, published: [ 1 ])
    open_sale!(free, 0)
    holder = User.create!(name: "보유", email: "home-holder@example.com", password: "password123", created_at: 30.days.ago)
    Commerce::ClaimFreeAccess.call!(user: holder, product_line: free.reload)
    sign_in(holder)
    get root_path
    assert_includes hero.text, "· 이용 중"
  end

  # --- c. track rows ---------------------------------------------------------------

  test "a row per track with listed series only, in /products order; an empty track prints nothing" do
    old = series("basics-old", track: "basics", summary: "먼저 만든 기초")
    newer = series("basics-new", track: "basics")
    series("basics-draft", track: "basics", status: "draft")
    series("no-track")

    get root_path
    basics = css_select("section[aria-labelledby='track-basics']").first
    assert basics
    assert_equal "개발 기초 시즌", basics.at_css("h2").text
    assert_includes basics.text, "개발환경부터 버전 관리까지, 손에 익히는 기초"
    hrefs = basics.css("a").map { |a| a["href"] }
    assert_equal [ product_line_path(old.slug), product_line_path(newer.slug) ], hrefs
    assert_includes basics.text, "먼저 만든 기초"
    assert_select "section[aria-labelledby='track-ai']", 0
    assert_no_match(/no-track/, basics.to_html)
  end

  test "a card's meta counts published and 공개 예정 episodes and carries the access_state label" do
    line = series("meta-line", track: "ai")
    episodes(line, published: [ 1, 2 ], drafts: [ 3 ])
    open_sale!(line, 0)

    get root_path
    card = css_select("section[aria-labelledby='track-ai'] a[href='#{product_line_path(line.slug)}']").first
    assert_includes card.text, "공개 2편 · 공개 예정 1편"
    assert_includes card.text, "무료"
    assert_nil card.at_css("a"), "the whole card is the only link"
  end

  test "the home still renders when there is no story series at all (older sections unchanged in R1)" do
    get root_path
    assert_response :success
    assert_nil hero
    assert_select "section[aria-labelledby^='track-']", 0
  end

  # --- a. admin ---------------------------------------------------------------------

  test "admin: the form sets track and featured, a second featured replaces the first, and the list shows it" do
    first = series("admin-a", featured: true)
    second = series("admin-b")
    draft = series("admin-c", status: "draft")
    sign_in(@admin)

    get edit_admin_product_line_path(second)
    assert_select "select[name='product_line[track]'] option[value='basics']", text: "개발 기초 시즌"
    assert_select "input[type=checkbox][name='product_line[featured]']"
    assert_match(/켜면 기존 대표 시리즈는 자동으로 해제됩니다/, response.body)

    patch admin_product_line_path(second), params: { product_line: { track: "ai", featured: "1" } }
    assert_redirected_to edit_admin_product_line_path(second)
    assert second.reload.featured?
    assert_equal "ai", second.track
    assert_not first.reload.featured?

    patch admin_product_line_path(draft), params: { product_line: { featured: "1" } }
    get admin_product_lines_path
    row = css_select("tr").find { |tr| tr.text.include?("시리즈 admin-c") }
    assert_includes row.text, "대표"
    assert_includes row.text, "비공개라 홈에 안 나옴"
    assert_not second.reload.featured?

    patch admin_product_line_path(draft), params: { product_line: { featured: "0" } }
    assert_equal 0, ProductLine.where(featured: true).count
  end
end
