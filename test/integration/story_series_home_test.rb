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


  # Handoff 0096 -- the featured guide is one card under the section heading "지금 시작하는 가이드".
  def hero = css_select("section[aria-labelledby='featured-guide-heading']").first
  def card_texts(card) = card.css("span, h3, p").map { |n| n.text.strip }.reject(&:empty?)

  # --- b. featured guide (0071 hero -> 0096 card) -----------------------------------

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

  test "the featured card: section heading, one link to the guide page, image -> badge -> name -> N편, no summary or buttons" do
    git = series("git-core", featured: true, summary: "변경 이력을 남기는 법부터")
    episodes(git, published: [ 1 ], drafts: [ 2, 3, 4, 5, 6 ])
    open_sale!(git, 0)

    get root_path
    assert hero, "featured card rendered"
    assert_equal "지금 시작하는 가이드", hero.at_css("h2#featured-guide-heading").text.strip
    links = hero.css("a")
    assert_equal 1, links.size, "the whole card is the only link (the arrow is part of it)"
    card = links.first
    assert_equal product_line_path(git.slug), card["href"]
    assert_equal "featured-guide-name", card["aria-labelledby"]
    image, text = card.element_children
    assert image.at_css("div[aria-hidden='true'].aspect-video"), "no cover -- the placeholder takes its place"
    assert_equal %w[span h3 div], text.element_children.map(&:name)
    assert_equal [ "무료", "시리즈 git-core", "1편", "→" ], card_texts(text) # 1 published + 5 upcoming -> 1편
    assert_equal "featured-guide-name", text.at_css("h3")["id"]
    assert_equal "true", text.css("span").last["aria-hidden"]
    [ "변경 이력을 남기는 법부터", "첫 편부터 보기", "가이드 소개", "공개 예정" ].each { |gone| assert_not_includes hero.text, gone }
    assert_no_match(/E0\d|S0\d/, hero.text)
  end

  test "the featured card with a cover: the image is the card's top, edge to edge" do
    line = series("cover-hero", featured: true)
    episodes(line, published: [ 1 ])
    line.cover_image.attach(io: file_fixture("covers/cover.jpg").open, filename: "c.jpg", content_type: "image/jpeg")
    line.update!(cover_image_alt: "표지")
    get root_path
    img = hero.at_css("a > div:first-child > img")
    assert_equal "표지", img["alt"]
    %w[block aspect-video w-full object-cover].each { |klass| assert_includes img["class"].split, klass }
    assert_not_includes img["class"].split, "rounded-2xl"
    assert_equal 1, hero.css("img").size
  end

  test "N편 counts published episodes only; none published reads 공개 예정" do
    fresh = series("fresh-line", featured: true)
    episodes(fresh, published: [], drafts: [ 1, 2 ])
    get root_path
    assert_equal "공개 예정", hero.at_css("h3 + div > span").text.strip
    assert_equal product_line_path(fresh.slug), hero.at_css("a")["href"]

    fresh.content_episodes.find_by!(position: 1).update!(status: "published")
    get root_path
    assert_equal "1편", hero.at_css("h3 + div > span").text.strip
  end

  test "the badge follows access_state: 무료 for a guest, a price, then 이용 중 for someone who owns it" do
    paid = series("paid-hero", featured: true)
    episodes(paid, published: [ 1 ])
    open_sale!(paid, 19_000)
    get root_path
    assert_equal "19,000원", hero.at_css("h3").previous_element.text.strip

    free = series("free-hero", featured: true)
    episodes(free, published: [ 1 ])
    open_sale!(free, 0)
    get root_path
    badge = hero.at_css("h3").previous_element
    assert_equal "무료", badge.text.strip
    assert_includes badge["class"].split, "inline-block"

    holder = User.create!(name: "보유", email: "home-holder@example.com", password: "password123", created_at: 30.days.ago)
    Commerce::ClaimFreeAccess.call!(user: holder, product_line: free.reload)
    sign_in(holder)
    get root_path
    assert_equal "이용 중", hero.at_css("h3").previous_element.text.strip
  end

  # R2 -- the two columns from md (was lg); md..lg has its own smaller values, lg and up as R1, stacked below md.
  test "card values: phone sizes, two columns from md with md values, lg values from lg" do
    line = series("sized-hero", featured: true)
    episodes(line, published: [ 1 ])
    get root_path
    assert_includes hero["class"].split, "px-2.5"
    card = hero.at_css("a")["class"].split
    %w[rounded-2xl overflow-hidden border bg-[#15181e] md:grid md:grid-cols-5 md:items-center].each { |k| assert_includes card, k }
    assert_empty card.grep(/\A(sm|lg):grid/), "no columns below md, nothing extra at lg"
    image, text = hero.at_css("a").element_children
    assert_equal [ "md:col-span-3" ], image["class"].split
    %w[px-3.5 pt-3 pb-3.5 md:col-span-2 md:p-5 lg:p-7].each { |k| assert_includes text["class"].split, k }
    name = hero.at_css("h3")["class"].split
    %w[font-display text-[22px] leading-[29px] md:text-[26px] md:leading-[34px] lg:text-[34px] lg:leading-[42px] break-keep break-words].each { |k| assert_includes name, k }
    arrow = hero.at_css("span[aria-hidden='true']")["class"].split
    %w[h-[34px] w-[34px] md:h-10 md:w-10 lg:h-11 lg:w-11 rounded-full].each { |k| assert_includes arrow, k }
    %w[pt-3.5 pb-[18px] sm:pt-8 sm:pb-9].each { |k| assert_includes hero["class"].split, k }
  end

  # --- c. track rows ---------------------------------------------------------------

  def track(name) = css_select("section[aria-labelledby='track-#{name}']").first
  def cards(section) = section.css(".grid > *")

  test "a row per track with listed series only, in /products order; an empty track prints nothing" do
    old = series("basics-old", track: "basics", summary: "먼저 만든 기초")
    newer = series("basics-new", track: "basics")
    series("basics-draft", track: "basics", status: "draft")
    series("no-track")

    get root_path
    basics = track("basics")
    assert basics
    assert_equal "개발 기초", basics.at_css("h2").text # 0091: ProductLine::TRACK_TITLES (no 시즌)
    hrefs = basics.css("a").map { |a| a["href"] }
    assert_equal [ product_line_path(old.slug), product_line_path(newer.slug) ], hrefs
    assert_not_includes basics.text, "먼저 만든 기초", "0096: no summary on the card"
    assert_no_match(/no-track/, basics.to_html)
    # No AI series here -- the AI row exists only because of the standalone products (handoff 0071 e).
    assert_empty track("ai").css("a[href^='/products/']")
  end

  # Handoff 0096 -- the heading's right side counts the cards actually drawn; the old tagline is gone.
  test "the row heading: the title and N개의 가이드 (the card count), no tagline" do
    series("count-a", track: "basics")
    series("count-b", track: "basics")
    series("count-c", track: "ai")
    get root_path
    basics = track("basics")
    assert_equal %w[h2 p], basics.at_css("div").element_children.map(&:name)
    assert_equal "2개의 가이드", basics.at_css("[data-track-count]").text.strip
    assert_equal 2, cards(basics).size
    assert_not_includes basics.text, "손에 익히는 기초"
    ai = track("ai")
    assert_equal "#{cards(ai).size}개의 가이드", ai.at_css("[data-track-count]").text.strip
    assert_equal 1 + Product.standalone.count, cards(ai).size
  end

  test "a card: image -> badge -> name -> N편 (published only), no summary, the whole card the only link" do
    line = series("meta-line", track: "ai", summary: "카드에 안 나오는 요약")
    episodes(line, published: [ 1, 2 ], drafts: [ 3 ])
    open_sale!(line, 0)
    empty = series("meta-empty", track: "ai")
    episodes(empty, published: [], drafts: [ 1 ])

    get root_path
    card = css_select("section[aria-labelledby='track-ai'] a[href='#{product_line_path(line.slug)}']").first
    image, text = card.element_children
    assert image.matches?("div[aria-hidden='true'].aspect-video")
    assert_equal %w[span h3 p], text.element_children.map(&:name)
    assert_equal [ "무료", "시리즈 meta-line", "2편" ], card_texts(text)
    assert_not_includes card.text, "카드에 안 나오는 요약"
    assert_nil card.at_css("a"), "the whole card is the only link"
    blank = css_select("section[aria-labelledby='track-ai'] a[href='#{product_line_path(empty.slug)}']").first
    assert_equal "공개 예정", blank.at_css("h3 + p").text.strip
  end

  test "the cards: two a row on phones and sm, four from lg; 10px side margins on phones" do
    series("grid-a", track: "basics")
    get root_path
    basics = track("basics")
    grid = basics.at_css(".grid")["class"].split
    %w[grid-cols-2 gap-2 sm:gap-4 lg:grid-cols-4].each { |k| assert_includes grid, k }
    assert_not_includes grid, "sm:grid-cols-1"
    %w[px-2.5 pt-[22px] pb-2 sm:px-7 sm:py-12].each { |k| assert_includes basics["class"].split, k }
    name = basics.at_css("h3")["class"].split
    %w[text-sm leading-5 break-keep break-words sm:text-base].each { |k| assert_includes name, k }
  end

  test "with no series at all: no hero, no basics row, the brand line is the heading, the AI row holds just the standalone products" do
    get root_path
    assert_response :success
    assert_nil hero
    assert_select "section[aria-labelledby='track-basics']", 0
    assert_select "h1", 1
    assert_select "h1#brand-line", 1
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


  # --- R2 d. 새로 공개 · 공개 예정 -- removed in 0096 -------------------------------------

  test "no 새로 공개 · 공개 예정 section, whatever episodes there are" do
    line = series("upd-a", track: "basics")
    line.content_episodes.create!(position: 1, customer_title: "막 공개된 편", status: "published", published_at: 1.hour.ago)
    line.content_episodes.create!(position: 2, customer_title: "곧 나올 편", status: "draft")
    get root_path
    assert_select "section[aria-labelledby='episode-updates']", 0
    assert_not_includes response.body, "새로 공개"
    assert_not_includes response.body, "막 공개된 편"
    assert_not_includes response.body, "곧 나올 편"
  end

  # --- R2 f. theme, header, fixed blocks --------------------------------------------------

  # Handoff 0091 (D-011) -- the brand sentence and the 가이드 · 에피소드 · 실전 blocks (no 시리즈 / 시즌).
  # Handoff 0096 -- the brand line is always the page's one h1 (the featured guide's name is an h3 under its h2).
  test "the fixed brand and guide / episode / practice copy, and the brand line is the one h1 with or without a featured guide" do
    get root_path
    assert_select "title", text: "LEEDOX | 실제로 만들고 부딪히며 엮은 개발자의 실전 가이드"
    assert_select "#brand-line", text: "실제로 만들고 부딪히며 엮은 개발자의 실전 가이드."
    assert_match(/매끈한 강의 대신, 막히고 고친 과정까지 한 편씩 따라갑니다\. Git·Java·WSL 같은 개발 기초부터 AI와 함께 만드는 이야기까지\./, response.body)
    assert_select "section[aria-labelledby='series-explainer'] h2", text: "가이드 · 에피소드 · 실전"
    blocks = css_select("section[aria-labelledby='series-explainer'] .grid > div").map { |d| d.css("p, h3").map { |n| n.text.strip } }
    assert_equal [
      [ "가이드", "하나의 주제, 하나의 완결", "Git, Java, WSL, AI 협업처럼 주제마다 가이드 하나. 그 자체로 끝까지 갑니다." ],
      [ "에피소드", "한 편에 한 장면", "각 편은 질문 하나에 답하고, 다음 편의 질문을 남기며 끝납니다." ],
      [ "실전", "부딪힌 자리까지", "잘 된 결과만이 아니라, 막히고 고친 과정을 그대로 엮었습니다." ]
    ], blocks

    series("hero-owner", featured: true)
    get root_path
    assert_select "h1", count: 1
    assert_select "h1#brand-line", 1
    assert_select "section[aria-labelledby='featured-guide-heading'] h3#featured-guide-name", text: "시리즈 hero-owner"
    html = response.body
    assert_operator html.index("featured-guide-heading"), :<, html.index('id="brand-line"'), "featured guide, then the brand line"
  end


  # Handoff 0083/0084 (D-010) -- the frame (header) is dark on every customer page; the body is dark on the home and
  # the series pages, light on the notices (it was /pricing until 0086 removed that page), and the display font only
  # loads where the body is dark (the full per-page check is test/integration/series_dark_theme_test.rb).
  test "the home is dark with the display font; the notices have the dark header but a light body and no font" do
    get root_path
    assert_select "div.bg-\\[\\#0e1014\\] > header.bg-\\[\\#0e1014\\]\\/90"
    assert_select "link[rel='preload'][href*='Pretendard-Bold']", 1

    get announcements_path
    assert_select "header.bg-\\[\\#0e1014\\]\\/90", 1
    assert_select "div.bg-\\[\\#0e1014\\] > header", 0
    assert_select "link[rel='preload'][href*='Pretendard-Bold']", 0
  end
end
