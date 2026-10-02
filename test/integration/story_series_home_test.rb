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
    assert_includes text, "공개 2편 · 공개 예정 3편"
    assert hero.at_css("a[href='#{product_episode_path(git.slug, '01')}']")&.text&.include?("첫 편부터 보기")
    assert_no_match(/E0\d/, text, "no episode numbers in the hero")
    assert hero.at_css("a[href='#{product_line_path(git.slug)}']")&.text&.include?("시리즈 소개")
    assert hero.at_css("div[aria-hidden='true'].aspect-video"), "no cover -- the placeholder takes its place"
  end

  test "the season slot uses the series' own label when set, S01 otherwise" do
    line = series("season-line", featured: true, series_label: "S02")
    episodes(line, published: [ 1 ])
    get root_path
    assert_includes hero.text, "지금 시작하는 시리즈 · S02 · 1편"
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
    assert_includes hero.text, "공개 예정 1편"
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
    assert_no_match(/no-track/, basics.to_html)
    # No AI series here -- the AI row exists only because of the standalone products (handoff 0071 e).
    ai = css_select("section[aria-labelledby='track-ai']").first
    assert_empty ai.css("a[href^='/products/']")
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

  test "with no series at all: no hero, no basics row, the brand line is the heading, the AI row holds just the standalone products" do
    get root_path
    assert_response :success
    assert_nil hero
    assert_select "section[aria-labelledby='track-basics']", 0
    assert_select "h1#brand-line", 1
    assert_select "section[aria-labelledby='episode-updates']", 0
    assert_select "section[aria-labelledby='track-ai'] [data-product-code]", Product.standalone.count
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

  # --- R2 d. 새로 공개 · 공개 예정 ------------------------------------------------------

  def updates = css_select("section[aria-labelledby='episode-updates'] ol > li")

  test "newest published episodes first (by published_at), then 공개 예정 ones; only listed series" do
    a = series("upd-a")
    b = series("upd-b")
    hidden = series("upd-hidden", status: "draft")
    a.content_episodes.create!(position: 1, customer_title: "A 오래된 편", status: "published", published_at: 3.days.ago, summary: "A의 한 줄 예고")
    b.content_episodes.create!(position: 1, customer_title: "B 최신 편", status: "published", published_at: 1.hour.ago)
    b.content_episodes.create!(position: 2, customer_title: "B 예정 편", status: "draft")
    hidden.content_episodes.create!(position: 1, customer_title: "비공개 제품의 편", status: "published", published_at: 1.minute.ago)

    get root_path
    cards = updates
    assert_equal [ "B 최신 편", "A 오래된 편", "B 예정 편" ], cards.map { |li| li.at_css("p.font-bold").text }
    assert_includes cards[0].text, "시리즈 upd-b"
    assert_no_match(/E0\d/, cards.map(&:text).join, "no episode numbers on the update cards")
    assert_includes cards[0].text, "공개"
    assert_equal product_episode_path(b.slug, "01"), cards[0].at_css("a")["href"]
    assert_includes cards[1].text, "A의 한 줄 예고"
    assert_nil cards[2].at_css("a"), "a 공개 예정 card is never a link"
    assert_includes cards[2].text, "공개 예정"
    assert_no_match(/비공개 제품의 편/, response.body)
  end

  test "an episode with no published_at falls back to updated_at for its place in the row" do
    line = series("upd-fallback")
    old = line.content_episodes.create!(position: 1, customer_title: "시각 없는 편", status: "published", published_at: nil)
    old.update_columns(updated_at: 1.minute.ago)
    line.content_episodes.create!(position: 2, customer_title: "어제 공개 편", status: "published", published_at: 1.day.ago)
    get root_path
    assert_equal [ "시각 없는 편", "어제 공개 편" ], updates.map { |li| li.at_css("p.font-bold").text }
  end

  test "at most 5 cards, two of them kept for 공개 예정 when there are that many; either half fills unused slots" do
    line = series("upd-many")
    6.times { |i| line.content_episodes.create!(position: i + 1, customer_title: "공개 #{i + 1}", status: "published", published_at: (10 - i).hours.ago) }
    3.times { |i| line.content_episodes.create!(position: i + 20, customer_title: "예정 #{i + 1}", status: "draft") }
    get root_path
    titles = updates.map { |li| li.at_css("p.font-bold").text }
    assert_equal [ "공개 6", "공개 5", "공개 4", "예정 1", "예정 2" ], titles

    line.content_episodes.draft.destroy_all
    get root_path
    assert_equal 5, updates.size, "no 공개 예정 -- published fills all five"
  end

  # --- R2 f. theme, header, fixed blocks --------------------------------------------------

  test "the fixed brand and series / season / episode copy, and the brand line steps down to <p> when a hero owns the h1" do
    get root_path
    assert_select "#brand-line", text: "실제로 만들고, 막히고, 고친 과정을 시즌과 에피소드로 따라갑니다."
    assert_match(/매끈한 강의 대신, 한 편씩 이어지는 시리즈/, response.body)
    { "하나의 주제, 하나의 이야기" => "주제마다 하나의 시리즈가 있습니다.",
      "한 단계씩 깊어지는 흐름" => "다음 시즌에서 한 단계 더 나아갑니다.",
      "한 편에 한 장면" => "다음 편의 질문을 남기며 끝납니다." }.each do |title, body|
      assert_select "section[aria-labelledby='series-explainer'] h3", text: title
      assert_match(/#{Regexp.escape(body)}/, response.body)
    end

    series("hero-owner", featured: true)
    get root_path
    assert_select "h1", count: 1
    assert_select "p#brand-line", 1
  end

  test "dark theme and the display font are the home's only: other pages keep the light header and don't load the font" do
    get root_path
    assert_select "div.bg-\\[\\#0e1014\\] > header.bg-\\[\\#0e1014\\]\\/90"
    assert_select "link[href*='fonts.googleapis.com'][href*='Gowun+Batang']", 1

    [ pricing_path, products_path ].each do |path|
      get path
      assert_select "header.bg-white\\/90", 1
      assert_select "link[href*='fonts.googleapis.com']", 0
    end
  end
end
