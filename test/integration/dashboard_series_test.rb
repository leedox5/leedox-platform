require "test_helper"

# Handoff 0080 -- the member dashboard's "이용 중인 시리즈" section, the corrected empty-state condition, the
# lower section renamed 더 둘러보기, and 만료 for a standalone product whose license ran out. Every judgment is
# an existing one (License#active_at? / #effective_status, ProductLine.customer_reachable, ContentEpisode.upcoming).
# Handoff 0085 R1 -- 더 둘러보기 lists series (not earlier products), so the tests that need it create a series
# that isn't in use; an earlier product without a usable license no longer shows at all (no 만료 / 미보유 card).
# Handoff 0089 -- the series card is the /products card: the whole card links to the series (no 첫 편부터 보기 button,
# no 시리즈 소개 link, 공개 N편 without the 공개 예정 count), the lower section is 다른 콘텐츠 (no line under it), and
# 가이드 둘러보기 → only shows in the empty state when there's nothing to browse either.
class DashboardSeriesTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @user = User.create!(name: "회원", email: "ds-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
  end

  def sign_in(user = @user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  # A series with its commerce product; published episodes at the given positions, titled drafts as 공개 예정.
  def series!(slug, name: "시리즈 #{slug}", summary: nil, published: [ 1 ], upcoming: [], status: "published", visibility: "public")
    line = ProductLine.create!(internal_name: slug, customer_name: name, slug: slug, introduction: "소개", summary: summary,
      status: status, visibility: visibility)
    line.update!(product: Product.create!(code: slug.tr("-", "_"), name: name))
    published.each { |p| line.content_episodes.create!(position: p, customer_title: "편 #{p}", body: "본문", status: "published") }
    upcoming.each { |p| line.content_episodes.create!(position: p, customer_title: "예정 #{p}", body: "본문", status: "draft") }
    line
  end

  def license!(product, starts_on: Date.current, last_usable_on: nil, source: "paid", status: "active")
    ends = last_usable_on && Time.zone.local((last_usable_on + 1).year, (last_usable_on + 1).month, (last_usable_on + 1).day)
    License.create!(user: @user, product: product, source: source, status: status,
      starts_on: starts_on, last_usable_on: last_usable_on, access_ends_at: ends)
  end

  def cards = css_select("section[aria-label='이용 중인 가이드'] [data-series-card]")
  def series_link_count = css_select("main a[href='#{products_path}']").count { |a| a.text.strip == "가이드 둘러보기 →" }

  # --- the series section --------------------------------------------------------------

  test "a series in use shows above everything: one link card with cover slot, name, summary, count, period and badge" do
    line = series!("git-core", name: "Git의 기본", summary: "변경 이력을 남기는 법부터", published: [ 1, 2 ], upcoming: [ 3 ])
    license!(line.product)
    series!("not-yet") # 0085: the lower section shows a series not in use
    sign_in
    get dashboard_path
    assert_response :success

    card = cards.sole
    text = card.text.squish
    assert_includes text, "Git의 기본"
    assert_includes text, "변경 이력을 남기는 법부터"
    assert_includes text, "공개 2편"
    assert_not_includes text, "공개 예정" # 0089: the list card's count line
    assert_includes text, "무기한 이용 중"
    assert_equal "이용 중", card.at_css("span.rounded-full").text.strip
    assert card.at_css("div[aria-hidden='true'].aspect-video"), "no cover image -- the 0068 placeholder"
    assert_equal "a", card.name, "the whole card is the link"
    assert_equal product_line_path("git-core", anchor: "episodes"), card["href"] # 0090: straight to the 에피소드 section
    assert_empty card.css("a")
    [ "첫 편부터 보기", "가이드 소개" ].each { |gone| assert_not_includes text, gone }
    html = response.body
    assert_operator html.index("이용 중인 가이드"), :<, html.index("다른 콘텐츠")
  end

  test "a dated license shows its end date; no summary means no summary line; no 공개 예정 means no suffix" do
    line = series!("dated", published: [ 1 ])
    license!(line.product, last_usable_on: Date.new(2027, 3, 5))
    sign_in
    get dashboard_path
    text = cards.sole.text.squish
    assert_includes text, "이용 종료일: 2027년 3월 5일"
    assert_includes text, "공개 1편"
    assert_not_includes text, "공개 예정"
  end

  test "several series: newest license first" do
    older = series!("older")
    newer = series!("newer")
    license!(older.product, starts_on: Date.current - 10)
    license!(newer.product, starts_on: Date.current - 1)
    sign_in
    get dashboard_path
    assert_equal %w[newer older], cards.map { |c| c["data-series-card"] }
  end

  test "a free start counts as in use" do
    line = series!("free-one")
    license!(line.product, source: "free")
    sign_in
    get dashboard_path
    assert_equal [ "free-one" ], cards.map { |c| c["data-series-card"] }
  end

  test "series a customer can't open, and licenses that aren't usable now, are left out" do
    license!(series!("draft-line", status: "draft").product)
    license!(series!("unlisted-line", visibility: "unlisted").product) # reachable by URL -> shown
    license!(series!("expired-line").product, starts_on: Date.current - 40, last_usable_on: Date.current - 10)
    license!(series!("canceled-line").product, status: "canceled")
    license!(series!("scheduled-line").product, starts_on: Date.current + 5)
    sign_in
    get dashboard_path
    assert_equal [ "unlisted-line" ], cards.map { |c| c["data-series-card"] }
  end

  test "a series with no published episode yet but a 공개 예정 one: the same link card, to its 에피소드 section" do
    line = series!("empty-line", published: [], upcoming: [ 1 ])
    license!(line.product)
    sign_in
    get dashboard_path
    card = cards.sole
    assert_equal product_line_path("empty-line", anchor: "episodes"), card["href"] # 0090: 공개 예정 cards are that section
    assert_includes card.text.squish, "공개 0편"
  end

  test "no series in use: no section, no empty heading" do
    sign_in
    get dashboard_path
    assert_select "section[aria-label='이용 중인 가이드']", 0
    assert_not_includes css_select("main").text, "이용 중인 가이드"
  end

  test "the series in use match what /mypage labels 이용 중" do
    in_use = series!("in-use", name: "이용 중 시리즈")
    gone = series!("gone", name: "끝난 시리즈")
    license!(in_use.product)
    license!(gone.product, starts_on: Date.current - 40, last_usable_on: Date.current - 10)
    sign_in
    get mypage_path
    mypage_in_use = css_select("[data-license-card]").filter_map do |card|
      card.at_css("h4").text.strip if card.at_css("span.rounded-full").text.strip == "이용 중"
    end
    get dashboard_path
    names = cards.map { |c| c.at_css("h3").text.strip }
    assert_equal [ "이용 중 시리즈" ], names
    assert_equal names, mypage_in_use & names
    assert_not_includes mypage_in_use, "끝난 시리즈"
  end

  # --- empty state: the four combinations ---------------------------------------------------

  test "empty box only when there's neither a series nor a standalone product in use" do
    line = series!("combo")
    chatdox = Product.find_by!(code: "chatdox")

    sign_in
    get dashboard_path # neither
    assert_select "section[aria-label='이용 중인 콘텐츠 없음']", 1
    assert_includes css_select("section[aria-label='이용 중인 콘텐츠 없음']").text, "아직 이용 중인 콘텐츠가 없습니다."
    assert_includes css_select("section[aria-label='이용 중인 콘텐츠 없음']").text, "아래에서 관심 있는 콘텐츠를 둘러보세요."

    license!(line.product) # series only
    get dashboard_path
    assert_select "section[aria-label='이용 중인 콘텐츠 없음']", 0
    assert_select "section[aria-label='이용 중인 가이드']", 1

    standalone = license!(chatdox, last_usable_on: Date.current + 30) # both
    get dashboard_path
    assert_select "section[aria-label='이용 중인 콘텐츠 없음']", 0
    assert_select "section[aria-label='Chatdox 현황']", 1
    assert_select "section[aria-label='이용 중인 가이드']", 1
    html = response.body
    assert_operator html.index("이용 중인 가이드"), :<, html.index("Chatdox 현황")

    License.where(product: line.product, user: @user).delete_all # standalone only
    get dashboard_path
    assert_select "section[aria-label='이용 중인 콘텐츠 없음']", 0
    assert_select "section[aria-label='이용 중인 가이드']", 0
    assert_select "section[aria-label='Chatdox 현황']", 1
    assert standalone
  end

  # --- 가이드 둘러보기 → and the lower section (0089) ------------------------------------------------

  test "가이드 둘러보기 → only in the empty state, when there's nothing to browse either" do
    sign_in
    get dashboard_path # nothing in use, nothing to browse
    assert_equal 1, series_link_count
    assert_select "section[aria-label='이용 중인 콘텐츠 없음'] a[href=?]", products_path, text: "가이드 둘러보기 →"

    series!("browse-line") # something to browse
    get dashboard_path
    assert_equal 0, series_link_count

    license!(series!("link-line").product) # a series in use
    get dashboard_path
    assert_equal 0, series_link_count
  end

  test "the lower section is 다른 콘텐츠, without a line under it" do
    series!("browse-line")
    sign_in
    get dashboard_path
    section = css_select("section[aria-label='다른 콘텐츠']").first
    assert_equal "다른 콘텐츠", section.at_css("h2").text.strip
    assert_not_includes section.text, "다른 이야기도 둘러보세요."
    assert_not_includes css_select("main").text, "더 둘러보기"
  end

  # --- earlier products without a usable license ------------------------------------------------

  # 0080 gave an expired earlier product a 만료 card (and others 미보유) under 더 둘러보기; 0085 takes earlier products
  # out of 더 둘러보기, so they show only while in use (and my page lists only active/scheduled ones since 0082).
  test "an expired, canceled-only or scheduled-only earlier product shows nowhere on the dashboard" do
    claudox = Product.find_by!(code: "claudox")
    chatdox = Product.find_by!(code: "chatdox")
    license!(claudox, starts_on: Date.current - 40, last_usable_on: Date.current - 10)
    license!(chatdox, starts_on: Date.current - 40, last_usable_on: Date.current - 10, status: "canceled")
    license!(chatdox, starts_on: Date.current + 3, last_usable_on: Date.current + 30)
    series!("browse-line")
    sign_in
    get dashboard_path
    text = css_select("main").text
    [ "Claudox", "Chatdox", "만료", "미보유", "이전 상품" ].each { |word| assert_not_includes text, word }
    assert_select "section[aria-label='이용 중인 콘텐츠 없음']", 1
    assert_select "section[aria-label='다른 콘텐츠'] [href=?]", product_line_path("browse-line")
  end

  test "a product with a usable license is never 만료 even with an older expired one" do
    chatdox = Product.find_by!(code: "chatdox")
    license!(chatdox, starts_on: Date.current - 60, last_usable_on: Date.current - 30)
    license!(chatdox, starts_on: Date.current - 1, last_usable_on: Date.current + 20)
    sign_in
    get dashboard_path
    assert_select "section[aria-label='Chatdox 현황'] span.rounded-full", text: "이용 중"
  end

  # Since 0082 my page leaves expired earlier products out (the order history keeps them); since 0085 so does the
  # dashboard -- the two agree again.
  test "an expired earlier product: neither the dashboard nor my page shows it" do
    claudox = Product.find_by!(code: "claudox")
    license!(claudox, starts_on: Date.current - 40, last_usable_on: Date.current - 10)
    sign_in
    get dashboard_path
    assert_not_includes css_select("main").text, "Claudox"
    get mypage_path
    assert_select "[data-license-card='claudox']", 0
  end

  # --- performance -------------------------------------------------------------------------------

  test "the number of queries doesn't grow with the number of series in use" do
    count_for = lambda do |n|
      User.where.not(id: @user.id).where("email LIKE ?", "ds-q-%").delete_all
      n.times { |i| license!(series!("q-#{n}-#{i}", published: [ 1, 2 ], upcoming: [ 3 ]).product) }
      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get dashboard_path }
      queries
    end
    sign_in
    one = count_for.call(1)
    three = count_for.call(2) # now 3 series in use
    assert_equal one, three, "1 series: #{one} queries, 3 series: #{three}"
  end

  test "the home hero and the dashboard share the first-episode button label" do
    view = ActionView::Base.empty
    view.extend(ProductLinesHelper)
    assert_equal "첫 편부터 보기", view.series_start_label
  end
end
