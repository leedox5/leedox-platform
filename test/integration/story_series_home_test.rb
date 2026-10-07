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
  # Handoff 0097 -- the heading is the operator's (that is still its default) and up to three cards.
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
    assert_equal "featured-guide-name-#{git.id}", card["aria-labelledby"]
    image, text = card.element_children
    assert image.at_css("div[aria-hidden='true'].aspect-video"), "no cover -- the placeholder takes its place"
    assert_equal %w[span h3 div], text.element_children.map(&:name)
    assert_equal [ "무료", "시리즈 git-core", "에피소드 1", "→" ], card_texts(text) # 1 published + 5 upcoming -> 에피소드 1 (0097)
    assert_equal "featured-guide-name-#{git.id}", text.at_css("h3")["id"]
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
    assert_equal "에피소드 1", hero.at_css("h3 + div > span").text.strip
  end

  test "the badge follows access_state: 무료 for a guest, a price, then 이용 중 for someone who owns it" do
    paid = series("paid-hero", featured: true)
    episodes(paid, published: [ 1 ])
    open_sale!(paid, 19_000)
    get root_path
    assert_equal "19,000원", hero.at_css("h3").previous_element.text.strip

    paid.update!(featured: false) # 0097: both could be featured now; keep one card to read
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
    assert_equal [ "무료", "시리즈 meta-line", "에피소드 2" ], card_texts(text)
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

  test "admin: the edit form sets track and 홈 대표 가이드 (it goes last), a fourth is refused, and the list shows the places" do
    first = series("admin-a", featured: true)
    second = series("admin-b")
    draft = series("admin-c", status: "draft")
    sign_in(@admin)

    get edit_admin_product_line_path(second)
    assert_select "select[name='product_line[track]'] option[value='basics']", text: "개발 기초 시즌"
    assert_select "input[type=checkbox][name='product_line[featured]']"
    assert_select "label", text: /홈 대표 가이드/
    assert_match(/켜면 홈 맨 위 대표 섹션의 맨 뒤에 들어갑니다\(최대 3개, 공개 가이드만 나옴\)/, response.body)
    assert_no_match(/대표 시리즈|자동으로 해제/, response.body)

    patch admin_product_line_path(second), params: { product_line: { track: "ai", featured: "1" } }
    assert_redirected_to edit_admin_product_line_path(second)
    assert_equal [ true, 2 ], [ second.reload.featured?, second.featured_position ]
    assert_equal "ai", second.track
    assert_equal 1, first.reload.featured_position, "the first one stays"
    get edit_admin_product_line_path(second)
    assert_select "input[type=checkbox][name='product_line[featured]'][checked]"
    assert_select "label", text: /지금 2번째/

    patch admin_product_line_path(draft), params: { product_line: { featured: "1" } }
    fourth = series("admin-d")
    patch admin_product_line_path(fourth), params: { product_line: { featured: "1" } }
    assert_response :unprocessable_entity
    assert_includes response.body, "대표 가이드는 3개까지입니다. 지금: 시리즈 admin-a, 시리즈 admin-b, 시리즈 admin-c"
    assert_not fourth.reload.featured?

    get admin_product_lines_path
    row = css_select("tr").find { |tr| tr.text.include?("시리즈 admin-c") }
    assert_includes row.text, "대표 3"
    assert_includes row.text, "비공개라 홈에 안 나옴"
    assert_includes css_select("tr").find { |tr| tr.text.include?("시리즈 admin-a") }.text, "대표 1"

    patch admin_product_line_path(draft), params: { product_line: { featured: "0" } }
    assert_equal 2, ProductLine.where(featured: true).count
  end

  # Handoff 0097 -- the list's 홈 대표 섹션 box: the title and the order, saved together, read back, shown on the home.
  test "admin: the 홈 대표 섹션 box saves the title and the order; the form and the home read them back" do
    a = series("box-a", featured: true)
    b = series("box-b", featured: true)
    c = series("box-c", featured: true)
    [ a, b, c ].each { |line| episodes(line, published: [ 1 ]) }
    sign_in(@admin)

    get admin_product_lines_path
    box = css_select("section[aria-labelledby='home-featured-box']").first
    assert_equal "지금 시작하는 가이드", box.at_css("input[name='home_title']")["placeholder"]
    assert_equal "30", box.at_css("input[name='home_title']")["maxlength"]
    assert_equal [ "시리즈 box-a", "시리즈 box-b", "시리즈 box-c" ], box.css("[data-home-featured-row] span.font-semibold").map(&:text)

    patch home_featured_admin_product_lines_path, params: { home_title: "BEST\n인기 가이드",
      positions: { a.id => "3", b.id => "1", c.id => "2" } }
    assert_redirected_to admin_product_lines_path
    follow_redirect!
    assert_select "input[name='home_title'][value=?]", "BEST 인기 가이드"
    assert_equal [ "시리즈 box-b", "시리즈 box-c", "시리즈 box-a" ],
      css_select("[data-home-featured-row] span.font-semibold").map(&:text)
    assert_select "[data-home-featured-row] select[name='positions[#{b.id}]'] option[selected]", text: "1번째"

    get root_path
    assert_equal "BEST 인기 가이드", hero.at_css("h2").text.strip
    assert_equal [ b, c, a ].map { |x| product_line_path(x.slug) }, hero.css("a").map { |x| x["href"] }

    # a repeat is refused: nothing is saved, the box comes back with what was typed
    patch home_featured_admin_product_lines_path, params: { home_title: "새로 만든 가이드", positions: { a.id => "1", b.id => "1", c.id => "2" } }
    assert_response :unprocessable_entity
    assert_includes response.body, "대표 순서가 겹칩니다"
    assert_select "input[name='home_title'][value=?]", "새로 만든 가이드"
    assert_equal "BEST 인기 가이드", SiteSetting.home_featured_title
    assert_equal 3, a.reload.featured_position

    patch home_featured_admin_product_lines_path, params: { home_title: "가" * 31, positions: { a.id => "3", b.id => "1", c.id => "2" } }
    assert_response :unprocessable_entity
    assert_includes response.body, "섹션 제목은 30자까지 쓸 수 있습니다."

    # a blank title is the default again; a blank place takes the guide off the home
    patch home_featured_admin_product_lines_path, params: { home_title: "", positions: { a.id => "", b.id => "1", c.id => "2" } }
    assert_not a.reload.featured?
    get root_path
    assert_equal "지금 시작하는 가이드", hero.at_css("h2").text.strip
    assert_equal 2, hero.css("a").size
  end

  test "admin: the box needs an admin" do
    member = User.create!(name: "회원", email: "box-m-#{SecureRandom.hex(3)}@example.com", password: "password123")
    sign_in(member)
    patch home_featured_admin_product_lines_path, params: { home_title: "몰래" }
    assert_equal "지금 시작하는 가이드", SiteSetting.home_featured_title
  end

  # --- 0097 B. two or three featured cards --------------------------------------------

  test "the operator's title is printed as plain text (no HTML), in the section's h2" do
    series("title-a", featured: true)
    SiteSetting.save_home_featured_title("<b>굵게</b> 가이드")
    get root_path
    assert_equal "<b>굵게</b> 가이드", hero.at_css("h2").text.strip
    assert_nil hero.at_css("h2 b")
  end

  test "one card is 0096's wide card; two or three sit in a row that scrolls sideways below md and is a grid from md" do
    a = series("row-a", featured: true)
    get root_path
    assert_nil hero.at_css("[data-featured-row]")
    assert_includes hero.at_css("a")["class"].split, "md:grid-cols-5"

    b = series("row-b", featured: true)
    get root_path
    row = hero.at_css("[data-featured-row]")
    %w[flex snap-x snap-mandatory gap-2.5 overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden md:grid md:grid-cols-2 md:gap-4 md:overflow-visible].each do |k|
      assert_includes row["class"].split, k
    end
    cards = row.css("> a")
    assert_equal [ a, b ].map { |x| product_line_path(x.slug) }, cards.map { |x| x["href"] }
    cards.each do |card|
      %w[flex w-[86%] shrink-0 snap-start flex-col md:w-auto overflow-hidden rounded-2xl].each { |k| assert_includes card["class"].split, k }
      assert_not_includes card["class"].split, "md:grid-cols-5"
      text = card.element_children.last
      %w[flex-1 flex-col px-3.5 pt-3 pb-3.5 md:px-[18px] md:pt-4 md:pb-[18px]].each { |k| assert_includes text["class"].split, k }
      assert_includes text.at_css("h3 + div")["class"].split, "mt-auto", "the count and arrow sit at the card's bottom"
      assert_equal card["aria-labelledby"], text.at_css("h3")["id"]
      %w[h-[34px] w-[34px] md:h-11 md:w-11].each { |k| assert_includes text.at_css("span[aria-hidden='true']")["class"].split, k }
    end
    assert_equal 2, hero.css("h3").map { |h| h["id"] }.uniq.size, "each card has its own name id"

    series("row-c", featured: true)
    get root_path
    assert_includes hero.at_css("[data-featured-row]")["class"].split, "md:grid-cols-3"
    assert_equal 3, hero.css("[data-featured-row] > a").size
  end

  test "the featured cards follow the operator's order and only listed guides; each carries its own state" do
    paid = series("ord-paid", featured: true)
    episodes(paid, published: [ 1, 2 ])
    open_sale!(paid, 19_000)
    hidden = series("ord-hidden", featured: true, status: "draft")
    free = series("ord-free", featured: true)
    open_sale!(free, 0)
    ProductLine.arrange_featured!({ paid.id.to_s => "2", hidden.id.to_s => "1", free.id.to_s => "3" })
    get root_path
    assert_equal [ product_line_path(paid.slug), product_line_path(free.slug) ], hero.css("a").map { |x| x["href"] }
    assert_equal [ [ "19,000원", "에피소드 2" ], [ "무료", "공개 예정" ] ],
      hero.css("a").map { |card| [ card.at_css("h3").previous_element.text.strip, card.at_css("h3 + div > span").text.strip ] }
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
    assert_select "section[aria-labelledby='featured-guide-heading'] h3[id^='featured-guide-name']", text: "시리즈 hero-owner"
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
