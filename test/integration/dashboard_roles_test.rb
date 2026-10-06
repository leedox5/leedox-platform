require "test_helper"

# Handoff 0085 R1 -- the dashboard answers "what can I watch": an earlier product shows while the member holds a paid
# license usable now (whether or not it is still on sale), under an 이전 상품 heading; 더 둘러보기 lists the series
# not in use (the /products card, the list's order, at most four) instead of earlier products. Handoff 0089 renamed
# that section 다른 콘텐츠 and made the earlier-product card a link to its contents.
class DashboardRolesTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    # Past the 7-day trial, so chapters open only through the license.
    @user = User.create!(name: "회원", email: "dr-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    @chatdox = Product.find_by!(code: "chatdox")
  end

  def sign_in(user = @user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def license!(product, starts_on: Date.current - 5, last_usable_on: Date.current + 25, source: "paid", status: "active")
    ends = last_usable_on && Time.zone.local((last_usable_on + 1).year, (last_usable_on + 1).month, (last_usable_on + 1).day)
    License.create!(user: @user, product: product, source: source, status: status,
      starts_on: starts_on, last_usable_on: last_usable_on, access_ends_at: ends)
  end

  def series!(slug, visibility: "public", status: "published")
    line = ProductLine.create!(internal_name: slug, customer_name: "시리즈 #{slug}", slug: slug, introduction: "소개",
      status: status, visibility: visibility)
    line.update!(product: Product.create!(code: slug.tr("-", "_"), name: "시리즈 #{slug}"))
    line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문", status: "published")
    line
  end

  def legacy_heading = css_select("main h2").select { |h| h.text.strip == "이전 상품" }
  def browse_slugs = css_select("section[aria-label='다른 콘텐츠'] a[href^='/products/']").map { |a| a["href"].delete_prefix("/products/") }

  # --- a. earlier products: by license, not by sale -------------------------------------------------

  test "an earlier product taken off sale still shows while in use, and its chapters still open" do
    @chatdox.update!(sale_enabled: false)
    @chatdox.product_offers.update_all(active: false)
    license!(@chatdox)
    sign_in
    get dashboard_path

    card = css_select("section[aria-label='Chatdox 현황']").sole
    assert_includes card.text, "이용 중"
    link = card.at_css("a") # 0089: the whole card links to the contents (was the 첫 챕터 시작 button)
    assert_equal product_content_index_path("chatdox"), link["href"]
    get link["href"]
    assert_response :success
    get product_chapter_path("chatdox", "20") # beyond the guest range -- opened by the license alone
    assert_response :success
  end

  # An inactive product's chapters 404 for everyone (ProductContentController#enforce_active_product), so it gets no
  # card that would lead nowhere -- reported in result.md.
  test "an inactive earlier product gets no card even with a license (its chapters are closed to everyone)" do
    @chatdox.update!(active: false)
    license!(@chatdox)
    sign_in
    get product_chapter_path("chatdox", "01")
    assert_response :not_found
    get dashboard_path
    assert_select "section[aria-label='Chatdox 현황']", 0
    assert_empty legacy_heading
  end

  test "expired, canceled, scheduled-only and free earlier products get no card" do
    license!(@chatdox, starts_on: Date.current - 40, last_usable_on: Date.current - 10)
    license!(@chatdox, status: "canceled")
    license!(Product.find_by!(code: "claudox"), starts_on: Date.current + 3, last_usable_on: Date.current + 30)
    license!(Product.find_by!(code: "aistart"), source: "free") # a free_access product
    sign_in
    get dashboard_path
    assert_empty css_select("section[aria-label$=' 현황']")
    assert_empty legacy_heading
    assert_select "section[aria-label='이용 중인 콘텐츠 없음']", 1
  end

  # --- b. the 이전 상품 heading -------------------------------------------------------------------

  test "이전 상품 heads the earlier-product cards, below the series in use" do
    license!(series!("in-use").product)
    license!(@chatdox)
    sign_in
    get dashboard_path
    assert_equal 1, legacy_heading.size
    html = response.body
    assert_operator html.index("이용 중인 가이드"), :<, html.index(">이전 상품<")
    assert_operator html.index(">이전 상품<"), :<, html.index("Chatdox 현황")
  end

  # Handoff 0089 -- only an earlier product in use: the one heading, then 이전 상품 and its card, then 다른 콘텐츠.
  test "only an earlier product in use: heading, 이전 상품 card, then 다른 콘텐츠 -- no empty box" do
    license!(@chatdox)
    series!("browse")
    sign_in
    get dashboard_path
    assert_select "h1", count: 1, text: "회원님이 이용 중인 콘텐츠"
    assert_select "section[aria-label='이용 중인 가이드']", 0
    assert_select "section[aria-label='이용 중인 콘텐츠 없음']", 0
    html = response.body
    assert_operator html.index("님이 이용 중인 콘텐츠</h1>"), :<, html.index(">이전 상품<")
    assert_operator html.index(">이전 상품<"), :<, html.index("Chatdox 현황")
    assert_operator html.index("Chatdox 현황"), :<, html.index(">다른 콘텐츠<")
  end

  test "no earlier product in use: no 이전 상품 heading" do
    license!(series!("in-use").product)
    sign_in
    get dashboard_path
    assert_empty legacy_heading
  end

  # --- c. 더 둘러보기 is series -----------------------------------------------------------------------

  test "더 둘러보기: the listed series not in use, in the list's order, at most four, with the list's card" do
    lines = %w[s1 s2 s3 s4 s5 s6].map { |slug| series!(slug) }
    series!("hidden", visibility: "unlisted") # not on /products
    license!(lines[1].product)
    sign_in
    get dashboard_path
    assert_equal %w[s1 s3 s4 s5], browse_slugs
    card = css_select("section[aria-label='다른 콘텐츠'] a[href='#{product_line_path("s1")}']").sole
    assert_equal "시리즈 s1", card.at_css("h3").text.strip
    assert_includes card.text.squish, "공개 1편"
    assert_includes card.text, "자세히 보기 →"
    assert card.at_css("span.rounded-full"), "the list's state badge"

    get products_path # the same order as the list
    listed = css_select("main a[href^='/products/']").map { |a| a["href"].delete_prefix("/products/") }
    assert_equal %w[s1 s3 s4 s5], (listed - %w[s2]).first(4)
  end

  test "the badges are the list's: 무료, N원 and 준비 중" do
    admin = User.create!(name: "관리자", email: "dr-adm-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    { "free-line" => 0, "paid-line" => 12_000, "ready-line" => nil }.each do |slug, amount|
      line = ProductLine.create!(internal_name: slug, customer_name: slug, slug: slug, introduction: "소개", status: "published")
      next if amount.nil?

      Commerce::ProductLineSales.set_price!(product_line: line, total_amount: amount, actor: admin)
      Commerce::ProductLineSales.start_sale!(product_line: line.reload, actor: admin)
    end
    sign_in
    badges = lambda do |scope|
      %w[free-line paid-line ready-line].to_h do |slug|
        [ slug, css_select("#{scope} a[href='#{product_line_path(slug)}'] span.rounded-full").first&.text&.strip ]
      end
    end
    get products_path
    list = badges.call("main")
    get dashboard_path
    dash = badges.call("section[aria-label='다른 콘텐츠']")
    assert_equal list, dash
    assert_equal({ "free-line" => "무료", "paid-line" => "12,000원" }, dash.slice("free-line", "paid-line"))
  end

  test "every listed series in use: no 더 둘러보기 section" do
    license!(series!("only").product)
    sign_in
    get dashboard_path
    assert_select "section[aria-label='다른 콘텐츠']", 0
    assert_select "main a[href=?]", products_path, text: "가이드 둘러보기 →", count: 0 # 0089: only in the empty state
  end

  test "더 둘러보기 never lists an earlier product" do
    series!("browse")
    sign_in
    get dashboard_path
    section = css_select("section[aria-label='다른 콘텐츠']").sole
    assert_no_match(/Chatdox|Claudox|가격 보기|미보유|만료/, section.text)
  end

  test "the number of queries stays bounded however many series there are to browse" do
    sign_in
    count = lambda do
      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get dashboard_path }
      queries
    end
    4.times { |i| series!("q#{i}") }
    four = count.call
    4.times { |i| series!("r#{i}") }
    assert_equal four, count.call
  end
end
