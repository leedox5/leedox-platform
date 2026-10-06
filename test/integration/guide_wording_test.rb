require "test_helper"

# Handoff 0091 (D-011) -- on customer screens a 시리즈 is called a 가이드 and 시즌 is gone (no season label like "S01"
# either). This walks the customer pages as a guest, a member before use and a member in use, and checks that the text
# the views produce has none of those words. The test data never uses them, so anything found came from a view,
# a helper or a fixed string. The terms quote the old name on purpose ("시리즈" in the revision note and the addendum
# that maps it onto 가이드) -- those quoted ones are the only exception.
class GuideWordingTest < ActionDispatch::IntegrationTest
  LEFTOVER = /시리즈|시즌|\bS\d{2}\b/

  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "gw-adm-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @member = User.create!(name: "회원", email: "gw-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    @guide = ProductLine.create!(internal_name: "g", customer_name: "깃 기초 가이드", slug: "git-guide", introduction: "## 시작\n\n본문",
      summary: "변경 이력을 남기는 법부터", status: "published", track: "basics", featured: true, series_label: "S01", series_key: "grp")
    @guide.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문", status: "published")
    @guide.content_episodes.create!(position: 2, customer_title: "다음 편", body: "본문", status: "draft")
    Commerce::ProductLineSales.set_price!(product_line: @guide, total_amount: 0, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: @guide.reload, actor: @admin)
    @other = ProductLine.create!(internal_name: "o", customer_name: "자바 웹앱 가이드", slug: "java-guide", introduction: "소개",
      status: "published", track: "basics")
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def page_text
    doc = Nokogiri::HTML(response.body)
    doc.css("script, style").each(&:remove)
    text = doc.text + doc.css("[aria-label]").map { |n| n["aria-label"] }.join(" ") +
      doc.css("title, meta[name='description']").map { |n| n["content"] || n.text }.join(" ")
    text.gsub("\"시리즈\"", "") # the terms quote the old name on purpose
  end

  def assert_no_leftover(path)
    get path
    assert_response :success, path
    found = page_text.scan(LEFTOVER).uniq
    assert_empty found, "#{path}: #{found.inspect}"
  end

  GUEST_PAGES = %w[/ /products /products/git-guide /products/java-guide /terms /privacy /notices /users/sign_in /users/sign_up].freeze

  test "a guest sees no 시리즈 / 시즌 / S01 on the customer pages" do
    GUEST_PAGES.each { |path| assert_no_leftover(path) }
  end

  test "a member before use: the same, plus the list's 내 가이드, my page and the dashboard" do
    sign_in(@member)
    (GUEST_PAGES - %w[/users/sign_in /users/sign_up] + %w[/products?filter=mine /mypage /dashboard /billing/checkout/git_guide]).each { |path| assert_no_leftover(path) }
    get products_path
    assert_select "nav[aria-label='가이드 필터'] a", text: /\A내 가이드/
  end

  test "a member in use: the purchase box, my page and the dashboard" do
    License.create!(user: @member, product: @guide.reload.product, source: "free", status: "active", starts_on: Date.current, last_usable_on: nil, access_ends_at: nil)
    sign_in(@member)
    %w[/products/git-guide /products/git-guide/01 /mypage /dashboard].each { |path| assert_no_leftover(path) }
    get product_line_path("git-guide")
    assert_includes css_select("#product-purchase").text, "무료로 이용 중인 가이드입니다 · 무기한 이용"
  end

  test "the header says 가이드 for guests, members and admins" do
    get root_path
    assert_select "nav[aria-label='주요 내비게이션'] a[href=?]", products_path, text: "가이드"
    sign_in(@admin)
    get admin_dashboard_path
    assert_select "nav[aria-label='주요 내비게이션'] a[href=?]", products_path, text: "가이드"
  end

  test "the home: brand title, the hero's label and button, the explainer and the row title" do
    get root_path
    assert_select "title", text: "LEEDOX | 실제로 만들고 부딪히며 엮은 개발자의 실전 가이드"
    assert_select "meta[name='description'][content=?]",
      "실제로 만들고 부딪히며 엮은 개발자의 실전 가이드. 매끈한 강의 대신, 막히고 고친 과정까지 한 편씩 따라갑니다. Git·Java·WSL 같은 개발 기초부터 AI와 함께 만드는 이야기까지."
    hero = css_select("section[aria-labelledby='featured-series-title']").first.text.squish
    assert_includes hero, "지금 시작하는 가이드 · 2편 · 무료"
    assert_includes hero, "가이드 소개"
    assert_select "#track-basics", text: "개발 기초"
  end

  test "the admin screens keep their wording for now (backlog 0068)" do
    sign_in(@admin)
    get edit_admin_product_line_path(@guide)
    assert_select "select[name='product_line[track]'] option[value='basics']", text: "개발 기초 시즌"
    assert_includes response.body, "시리즈 키"
  end
end
