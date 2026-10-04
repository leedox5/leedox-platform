require "test_helper"

# Handoff 0081 R1 -- /mypage's "상품별 라이선스": one card per product (a series shown as that series, under its
# current name), 이용 중 -> 이용 예정 -> 무료 이용 -> 만료, other records folded into "지난 기록 N건", a 콘텐츠 보기 link
# on cards in use, the footer and the title. Purchase links and the order history stay exactly as they were.
class MypageLicenseCardsTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @user = User.create!(name: "회원", email: "mp-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 60.days.ago)
    @chatdox = Product.find_by!(code: "chatdox")
    @claudox = Product.find_by!(code: "claudox")
  end

  def sign_in(user = @user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def license!(product, starts_on:, last_usable_on: nil, status: "active", source: "paid")
    ends = last_usable_on && Time.zone.local((last_usable_on + 1).year, (last_usable_on + 1).month, (last_usable_on + 1).day)
    License.create!(user: @user, product: product, source: source, status: status,
      starts_on: starts_on, last_usable_on: last_usable_on, access_ends_at: ends)
  end

  def series!(slug, name:, status: "published", visibility: "public")
    line = ProductLine.create!(internal_name: slug, customer_name: name, slug: slug, introduction: "소개", status: status, visibility: visibility)
    line.update!(product: Product.create!(code: slug.tr("-", "_"), name: "옛 이름 #{slug}"))
    line
  end

  def cards = css_select("section[aria-label='상품별 라이선스'] [data-license-card]")
  def card(code) = css_select("[data-license-card='#{code}']").first
  def badge(node) = node.at_css("span.rounded-full").text.strip
  def period(node) = node.css("p.mt-3").first.text.strip

  # --- one card per product ------------------------------------------------------------------

  test "several records of a product make one card; 이용 중 beats the rest and the others fold into 지난 기록" do
    license!(@chatdox, starts_on: Date.new(2026, 6, 24), last_usable_on: Date.new(2026, 7, 23))
    license!(@chatdox, starts_on: Date.new(2026, 8, 24), last_usable_on: Date.new(2026, 9, 23))
    license!(@chatdox, starts_on: Date.current - 10, last_usable_on: Date.current + 19, status: "canceled")
    current = license!(@chatdox, starts_on: Date.current - 10, last_usable_on: Date.new(2026, 10, 23).then { |d| d < Date.current ? Date.current + 19 : d })
    sign_in
    get mypage_path
    assert_response :success

    assert_equal 1, css_select("[data-license-card='chatdox']").size
    chatdox = card("chatdox")
    assert_equal "이용 중", badge(chatdox)
    assert_equal "이용 종료일: #{I18n.l(current.last_usable_on, format: :long, locale: :ko)}", period(chatdox)
    details = chatdox.at_css("details")
    assert_equal "지난 기록 3건", details.at_css("summary").text.strip
    lines = details.css("li").map { |li| li.text.squish }
    assert_equal 3, lines.size
    assert lines.first.end_with?("· 취소"), "most recent first: #{lines.inspect}"
    assert_equal [ "· 만료", "· 만료" ], lines.last(2).map { |l| l[/· \S+\z/] }
    assert_select "[data-license-card='chatdox'] a[href=?]", "/chatdox", text: "콘텐츠 보기"
  end

  test "이용 예정 beats 만료; 만료 alone shows the latest end" do
    license!(@chatdox, starts_on: Date.current - 60, last_usable_on: Date.current - 30)
    license!(@chatdox, starts_on: Date.current + 5, last_usable_on: Date.current + 35)
    license!(@claudox, starts_on: Date.new(2026, 6, 22), last_usable_on: Date.new(2026, 7, 21))
    license!(@claudox, starts_on: Date.new(2026, 7, 22), last_usable_on: Date.new(2026, 8, 21))
    sign_in
    get mypage_path
    assert_equal "이용 예정", badge(card("chatdox"))
    assert_equal "#{I18n.l(Date.current + 5, format: :long, locale: :ko)}부터 이용 예정", period(card("chatdox"))
    assert_nil card("chatdox").at_css("a"), "no link on a 이용 예정 card"
    assert_equal "만료", badge(card("claudox"))
    assert_equal "이용 기간이 끝났습니다 (2026년 8월 21일까지)", period(card("claudox"))
    assert_equal "지난 기록 1건", card("claudox").at_css("summary").text.strip
    assert_nil card("claudox").at_css("a"), "no link on a 만료 card"
  end

  test "a product with only canceled records gets no card" do
    license!(@claudox, starts_on: Date.current - 10, last_usable_on: Date.current + 20, status: "canceled")
    sign_in
    get mypage_path
    assert_nil card("claudox")
  end

  test "a single record has no 지난 기록 area" do
    license!(@claudox, starts_on: Date.current - 40, last_usable_on: Date.current - 10)
    sign_in
    get mypage_path
    assert_nil card("claudox").at_css("details")
  end

  # --- order ---------------------------------------------------------------------------------------

  test "order: 이용 중 (newest start first, series and products mixed) -> 이용 예정 -> 무료 -> 만료 (latest end first)" do
    old_series = series!("old-series", name: "먼저 시작한 시리즈")
    license!(old_series.product, starts_on: Date.current - 20)
    license!(@chatdox, starts_on: Date.current - 5, last_usable_on: Date.current + 25)
    license!(@claudox, starts_on: Date.current - 90, last_usable_on: Date.current - 60)
    ended_later = series!("ended-later", name: "나중에 끝난 시리즈")
    license!(ended_later.product, starts_on: Date.current - 40, last_usable_on: Date.current - 10)
    soon = series!("soon", name: "곧 시작할 시리즈")
    license!(soon.product, starts_on: Date.current + 3, last_usable_on: Date.current + 30)
    sign_in
    get mypage_path
    order = cards.map { |c| c["data-license-card"] }
    free = Product.active.where(free_access: true).order(:code).pluck(:code)
    assert_equal [ "chatdox", "old_series", "soon", *free, "ended_later", "claudox" ], order
  end

  # --- series ----------------------------------------------------------------------------------------

  test "a series card uses the series' current name and links to its page; the order history keeps the paid name" do
    line = series!("git-core", name: "Git의 기본")
    license!(line.product, starts_on: Date.current - 1)
    sign_in
    get mypage_path
    git = card("git_core")
    assert_equal "Git의 기본", git.at_css("h3").text.strip
    assert_not_includes git.text, "옛 이름"
    assert_equal "무기한 이용 중", period(git)
    assert_select "[data-license-card='git_core'] a[href=?]", product_line_path("git-core"), text: "콘텐츠 보기"
    # (The order history's paid-time names are covered by the purchase-links / order-history test below.)
  end

  test "a series a customer can't open gets no link; a series link that's gone falls back to the product name" do
    hidden = series!("hidden-line", name: "닫힌 시리즈", status: "draft")
    license!(hidden.product, starts_on: Date.current - 1)
    orphan = Product.create!(code: "orphan_product", name: "연결 끊긴 상품")
    license!(orphan, starts_on: Date.current - 2, last_usable_on: Date.current + 28)
    sign_in
    get mypage_path
    assert_equal "닫힌 시리즈", card("hidden_line").at_css("h3").text.strip
    assert_nil card("hidden_line").at_css("a")
    assert_equal "연결 끊긴 상품", card("orphan_product").at_css("h3").text.strip
  end

  # --- free, empty, footer, title -----------------------------------------------------------------------

  test "free product cards are unchanged; with no paid record the empty line stays" do
    sign_in
    get mypage_path
    aistart = card("aistart")
    assert_equal "무료 이용", badge(aistart)
    assert_equal "전체 이용 가능 · 기간 제한 없음", period(aistart)
    assert_select "[data-license-card='aistart'] a[href=?]", "/content/aistart", text: "콘텐츠 보기"
    assert_includes css_select("section[aria-label='상품별 라이선스']").text, "아직 유료 상품 라이선스가 없습니다."
  end

  test "title and footer" do
    sign_in
    get mypage_path
    assert_select "title", text: "마이페이지 | LEEDOX"
    assert_select "footer a[href=?]", announcements_path, text: "공지"
    assert_select "footer a[href=?]", terms_path
  end

  # --- untouched: purchase links and order history --------------------------------------------------------

  test "no purchase links (R2); the order history (status, refund and retry buttons, paid names) is unchanged" do
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    @claudox.update!(sale_enabled: true)
    admin = User.create!(name: "관리자", email: "mp-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    offer = @claudox.product_offers.active.ordered.first
    paid = Commerce::OrderCreator.call!(user: @user, product_code: "claudox", offer_code: offer.code, requested_start_on: nil, provider: "manual")
    Commerce::ConfirmManualPayment.call!(order: paid, actor: admin)
    abandoned = Commerce::OrderCreator.call!(user: @user, product_code: "claudox", offer_code: offer.code, requested_start_on: nil, provider: "manual")
    abandoned.update_columns(status: "abandoned")
    sign_in
    get mypage_path

    # R2: the "{상품} 구매" line is gone even while Claudox is on sale; the orders below are untouched.
    assert_empty css_select("section[aria-label='상품별 라이선스'] a").select { |a| a.text.strip.end_with?("구매") }
    orders = css_select("li").select { |li| li.text.include?("주문번호") }
    paid_row = orders.find { |li| li.text.include?("결제 완료") }
    abandoned_row = orders.find { |li| li.text.include?("결제 이탈") }
    assert paid_row.text.include?("Claudox")
    assert paid_row.at_css("a[href='#{new_billing_order_refund_request_path(paid.public_id)}']"), "환불 요청 stays"
    assert abandoned_row.at_css("a[href='#{retry_billing_order_path(abandoned.public_id)}']"), "새 주문으로 재시도 stays"
  ensure
    ENV.delete("LEEDOX_COMMERCE_ENABLED")
  end

  # --- R2 ------------------------------------------------------------------------------------------------------

  test "R2: no dashboard link on the account card, no purchase line; R1 cards, title and footer unchanged" do
    @chatdox.update!(sale_enabled: true)
    license!(@chatdox, starts_on: Date.current - 5, last_usable_on: Date.current + 25)
    license!(@claudox, starts_on: Date.current - 40, last_usable_on: Date.current - 10)
    sign_in
    get mypage_path
    account = css_select("article").find { |a| a.at_css("h2")&.text&.strip == "계정 정보" }
    assert account
    assert_nil account.at_css("a[href='#{dashboard_path}']")
    assert_not_includes response.body, "진행률은 대시보드에서"
    section = css_select("section[aria-label='상품별 라이선스']").first
    assert_equal "상품별 라이선스", section.at_css("h2").text.strip
    assert_empty section.css("a").select { |a| a.text.strip.end_with?("구매") }
    assert_not_includes section.text, "신규 판매 준비 중"
    assert_equal "이용 중", badge(card("chatdox"))
    assert_equal "만료", badge(card("claudox"))
    assert_select "[data-license-card='chatdox'] a[href=?]", "/chatdox", text: "콘텐츠 보기"
    assert_select "title", text: "마이페이지 | LEEDOX"
    assert_select "footer"
  end

  test "R2: buying and extending stay reachable from /pricing and the product page" do
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    @chatdox.update!(sale_enabled: true)
    license!(@chatdox, starts_on: Date.current - 5, last_usable_on: Date.current + 25)
    sign_in
    get pricing_path
    assert_select "a[href='/chatdox']", text: "자세히 보기"
    get "/chatdox"
    checkout = css_select("a").select { |a| a["href"].to_s.include?("checkout") }
    assert checkout.any?, "the product page still links to checkout for a member already using it"
    get checkout.first["href"]
    assert_response :success
    assert_includes response.body, (@chatdox.licenses.where(user: @user).first.last_usable_on + 1).strftime("%Y-%m-%d"),
      "checkout offers the extension start date (day after the current license)"
  ensure
    ENV.delete("LEEDOX_COMMERCE_ENABLED")
  end

  test "guests are sent to sign in" do
    get mypage_path
    assert_redirected_to new_user_session_path
  end
end
