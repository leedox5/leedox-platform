require "test_helper"

# Handoff 0090 -- a series page has a sticky 소개 · 에피소드 bar right under the purchase box, linking to #intro and
# #episodes (permanent addresses). A section that isn't on the page gets no link, and one link or fewer means no bar --
# decided by the same conditions that draw the sections. The dashboard's in-use card jumps to #episodes.
class SeriesSectionNavTest < ActionDispatch::IntegrationTest
  NAV = "nav[aria-label='시리즈 바로가기']"

  setup do
    @admin = User.create!(name: "관리자", email: "sn-adm-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @user = User.create!(name: "회원", email: "sn-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    @line = series!("nav-line", published: [ 1, 2 ])
  end

  def series!(slug, published: [], upcoming: [])
    line = ProductLine.create!(internal_name: slug, customer_name: "시리즈 #{slug}", slug: slug, introduction: "## 첫 제목\n\n소개 본문",
      status: "published")
    published.each { |p| line.content_episodes.create!(position: p, customer_title: "편 #{p}", body: "본문", status: "published") }
    upcoming.each { |p| line.content_episodes.create!(position: p, customer_title: "예정 #{p}", body: "본문", status: "draft") }
    line
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def nav_links = css_select("#{NAV} a").map { |a| [ a.text.strip, a["href"] ] }

  test "the bar sits right under the purchase box, before the introduction, with the two links and both targets" do
    Commerce::ProductLineSales.set_price!(product_line: @line, total_amount: 0, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: @line.reload, actor: @admin)
    get product_line_path("nav-line")
    assert_response :success
    assert_equal [ [ "소개", "#intro" ], [ "에피소드", "#episodes" ] ], nav_links
    assert_select "#intro h2", text: "소개"
    assert_select "h2#episodes", text: "에피소드"
    body = response.body
    assert_operator body.index('id="product-purchase"'), :<, body.index("시리즈 바로가기")
    assert_operator body.index("시리즈 바로가기"), :<, body.index('id="intro"')
    assert_operator body.index('id="intro"'), :<, body.index('id="episodes"')
  end

  test "the bar is sticky under the header, on its own background, and the targets clear both bars" do
    get product_line_path("nav-line")
    nav = css_select(NAV).first
    classes = nav["class"].split
    assert_includes classes, "sticky"
    assert_includes classes, "top-[64px]"    # header 65px on mobile, minus 1px under its border
    assert_includes classes, "md:top-[62px]" # header 63px from md up
    assert_includes classes, "bg-[#0e1014]"
    assert_equal "section-nav", nav["data-controller"]
    assert_includes css_select("#intro").first["class"].split, "scroll-mt-28"
    assert_includes css_select("#episodes").first["class"].split, "scroll-mt-28"
  end

  test "guests, members before use, members in use and admins all get the same bar" do
    expected = [ [ "소개", "#intro" ], [ "에피소드", "#episodes" ] ]
    get product_line_path("nav-line")
    assert_equal expected, nav_links, "guest"

    sign_in(@user)
    get product_line_path("nav-line")
    assert_equal expected, nav_links, "member, not in use"

    @line.update!(product: Product.create!(code: "nav_line", name: "nav"))
    License.create!(user: @user, product: @line.product, source: "free", status: "active", starts_on: Date.current, last_usable_on: nil, access_ends_at: nil)
    get product_line_path("nav-line")
    assert_equal expected, nav_links, "member, in use"

    delete destroy_user_session_path
    sign_in(@admin)
    get product_line_path("nav-line")
    assert_equal expected, nav_links, "admin"
  end

  test "공개 예정 episodes alone still make an 에피소드 section" do
    series!("coming-line", upcoming: [ 1 ])
    get product_line_path("coming-line")
    assert_equal [ "소개", "에피소드" ], nav_links.map(&:first)
  end

  test "no episodes at all: the page shows 준비 중입니다., no 에피소드 link, and with one link left no bar" do
    series!("empty-line")
    get product_line_path("empty-line")
    assert_includes css_select("main").text, "준비 중입니다."
    assert_select "#episodes", 0
    assert_select NAV, 0
    assert_select "#intro", 1
  end

  test "the bar's items come from the conditions that draw the sections" do
    view = ActionView::Base.empty
    view.extend(ProductLinesHelper)
    line = ProductLine.new(introduction: "")
    assert_equal [], view.series_section_nav_items(line, [], [])
    line.introduction = "소개"
    assert_equal [ [ "소개", "intro" ] ], view.series_section_nav_items(line, [], [])
    assert_equal [ [ "소개", "intro" ], [ "에피소드", "episodes" ] ], view.series_section_nav_items(line, [ :episode ], [])
    assert_equal [ [ "에피소드", "episodes" ] ], view.series_section_nav_items(ProductLine.new(introduction: ""), [], [ :upcoming ])
  end

  test "the admin preview has no bar and no customer anchors" do
    sign_in(@admin)
    get admin_product_line_path(@line)
    assert_response :success
    assert_select NAV, 0
    assert_select "h2#episodes", 0
  end

  # --- the dashboard -------------------------------------------------------------------------------

  test "the dashboard's in-use card jumps to #episodes; without an 에피소드 section it goes to the page; 다른 콘텐츠 unchanged" do
    @line.update!(product: Product.create!(code: "nav_line", name: "nav"))
    empty = series!("empty-line")
    empty.update!(product: Product.create!(code: "empty_line", name: "empty"))
    other = series!("other-line", published: [ 1 ])
    [ @line, empty ].each do |line|
      License.create!(user: @user, product: line.product, source: "free", status: "active", starts_on: Date.current, last_usable_on: nil, access_ends_at: nil)
    end
    sign_in(@user)
    get dashboard_path
    hrefs = css_select("section[aria-label='이용 중인 시리즈'] [data-series-card]").to_h { |a| [ a["data-series-card"], a["href"] ] }
    assert_equal "/products/nav-line#episodes", hrefs["nav-line"]
    assert_equal "/products/empty-line", hrefs["empty-line"]
    assert_select "section[aria-label='다른 콘텐츠'] a[href=?]", product_line_path(other.slug)

    get products_path # the series list's links are unchanged
    assert_select "main a[href=?]", "/products/nav-line"
    assert_select "main a[href*='#episodes']", 0
  end
end
