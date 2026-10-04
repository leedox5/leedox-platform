require "test_helper"

# /mypage "상품별 라이선스".
# Handoff 0081 -- one card per product (a series shown as that series, under its current name), 이용 중 -> 이용 예정
# -> 만료, other records folded into "지난 기록 N건", 콘텐츠 보기 while in use; footer and title; R2 removed the
# dashboard link and the purchase line.
# Handoff 0082 -- two parts: 시리즈 (everything above, always shown, an empty line + link when none) and 이전 상품
# (paid standalone products in use or scheduled only; no expired, no free, no past records; hidden when empty).
# The order history stays exactly as it was.
# Handoff 0085 R2 -- the same records as one-line rows in a divided list (not a card grid), without 콘텐츠 보기.
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

  def part(label) = css_select("section[aria-label='#{label}']").first
  def codes(label) = (part(label)&.css("[data-license-card]") || []).map { |c| c["data-license-card"] }
  def card(code) = css_select("[data-license-card='#{code}']").first
  def badge(node) = node.at_css("span.rounded-full").text.strip
  def period(node) = node.at_css("div > p").text.strip

  # --- the two parts (0082) -------------------------------------------------------------------------

  test "시리즈 comes first, 이전 상품 second, under the unchanged outer title" do
    license!(series!("git-core", name: "Git의 기본").product, starts_on: Date.current - 1)
    license!(@chatdox, starts_on: Date.current - 5, last_usable_on: Date.current + 25)
    sign_in
    get mypage_path
    outer = css_select("section[aria-label='상품별 라이선스']").first
    assert_equal "상품별 라이선스", outer.at_css("h2").text.strip
    assert_equal [ "시리즈", "이전 상품" ], outer.css("section > h3").map { |h| h.text.strip }
    assert_equal [ "git_core" ], codes("시리즈")
    assert_equal [ "chatdox" ], codes("이전 상품")
  end

  test "no license at all: 시리즈 shows its empty line and link; no 이전 상품 part; no free cards; no old empty line" do
    sign_in
    get mypage_path
    series = part("시리즈")
    assert_includes series.text, "아직 이용 중인 시리즈가 없습니다."
    assert_equal products_path, series.css("a").find { |a| a.text.strip == "시리즈 둘러보기 →" }["href"]
    assert_nil part("이전 상품")
    assert_select "[data-license-card]", 0
    assert_not_includes response.body, "무료 이용"
    assert_not_includes response.body, "아직 유료 상품 라이선스가 없습니다."
  end

  test "이전 상품: in use and scheduled only; expired-only, canceled-only and free products get no card" do
    license!(@chatdox, starts_on: Date.current + 3, last_usable_on: Date.current + 30)   # scheduled
    license!(@claudox, starts_on: Date.current - 40, last_usable_on: Date.current - 10)   # expired only
    aistart = Product.find_by!(code: "aistart")
    license!(aistart, starts_on: Date.current - 1, last_usable_on: Date.current + 30)   # free product, in use
    sign_in
    get mypage_path
    assert_equal [ "chatdox" ], codes("이전 상품")
    assert_equal "이용 예정", badge(card("chatdox"))
    assert_equal "#{I18n.l(Date.current + 3, format: :long, locale: :ko)}부터 이용 예정", period(card("chatdox"))
    assert_nil card("chatdox").at_css("a"), "no link on a 이용 예정 card"
    assert_nil card("claudox")
    assert_nil card("aistart")

    License.where(product: @chatdox, user: @user).update_all(status: "canceled") # canceled only
    get mypage_path
    assert_nil part("이전 상품"), "no cards -> no 이전 상품 part at all"
  end

  test "이전 상품 in use: one card, period line, no link (0085), never 지난 기록" do
    license!(@chatdox, starts_on: Date.new(2026, 6, 24), last_usable_on: Date.new(2026, 7, 23))
    license!(@chatdox, starts_on: Date.new(2026, 8, 24), last_usable_on: Date.new(2026, 9, 23))
    license!(@chatdox, starts_on: Date.current - 10, last_usable_on: Date.current + 19, status: "canceled")
    current = license!(@chatdox, starts_on: Date.current - 10, last_usable_on: Date.current + 19)
    sign_in
    get mypage_path
    assert_equal 1, css_select("[data-license-card='chatdox']").size
    chatdox = card("chatdox")
    assert_equal "이용 중", badge(chatdox)
    assert_equal "이용 종료일: #{I18n.l(current.last_usable_on, format: :long, locale: :ko)}", period(chatdox)
    assert_nil chatdox.at_css("a"), "0085: no 콘텐츠 보기"
    assert_nil chatdox.at_css("details"), "past records stay in the order history"
  end

  test "이전 상품 with in use + scheduled (an extension) is one 이용 중 card" do
    license!(@chatdox, starts_on: Date.current - 5, last_usable_on: Date.current + 10)
    license!(@chatdox, starts_on: Date.current + 11, last_usable_on: Date.current + 40)
    sign_in
    get mypage_path
    assert_equal [ "chatdox" ], codes("이전 상품")
    assert_equal "이용 중", badge(card("chatdox"))
  end

  test "earlier products only, no series: the 시리즈 empty line plus the 이전 상품 card" do
    license!(@chatdox, starts_on: Date.current - 5, last_usable_on: Date.current + 25)
    sign_in
    get mypage_path
    assert_includes part("시리즈").text, "아직 이용 중인 시리즈가 없습니다."
    assert_equal [ "chatdox" ], codes("이전 상품")
  end

  # --- 시리즈 part: 0081 unchanged ---------------------------------------------------------------------

  test "series: one card per series, 이용 중 beats the rest, other records fold into 지난 기록" do
    line = series!("git-core", name: "Git의 기본")
    license!(line.product, starts_on: Date.new(2026, 6, 1), last_usable_on: Date.new(2026, 6, 30))
    license!(line.product, starts_on: Date.new(2026, 7, 1), last_usable_on: Date.new(2026, 7, 31), status: "canceled")
    license!(line.product, starts_on: Date.current - 1)
    sign_in
    get mypage_path
    git = card("git_core")
    assert_equal 1, css_select("[data-license-card='git_core']").size
    assert_equal "Git의 기본", git.at_css("h4").text.strip
    assert_not_includes git.text, "옛 이름"
    assert_equal "이용 중", badge(git)
    assert_equal "무기한 이용 중", period(git)
    assert_nil git.at_css("a"), "0085: no 콘텐츠 보기"
    assert_equal "지난 기록 2건", git.at_css("summary").text.strip
    lines = git.css("details li").map { |li| li.text.squish }
    assert lines.first.end_with?("· 취소") && lines.last.end_with?("· 만료"), "most recent first: #{lines.inspect}"
  end

  test "series: a single record has no 지난 기록; an expired series shows 만료 with no link" do
    license!(series!("one", name: "하나").product, starts_on: Date.current - 1)
    gone = series!("gone", name: "끝난 시리즈")
    license!(gone.product, starts_on: Date.current - 40, last_usable_on: Date.current - 10)
    sign_in
    get mypage_path
    assert_nil card("one").at_css("details")
    assert_equal "만료", badge(card("gone"))
    assert_equal "이용 기간이 끝났습니다 (#{I18n.l(Date.current - 10, format: :long, locale: :ko)}까지)", period(card("gone"))
    assert_nil card("gone").at_css("a")
  end

  test "series order: 이용 중 (newest start) -> 이용 예정 -> 만료 (latest end); canceled-only gets no card" do
    older = series!("older", name: "먼저")
    license!(older.product, starts_on: Date.current - 20)
    newer = series!("newer", name: "나중")
    license!(newer.product, starts_on: Date.current - 2)
    soon = series!("soon", name: "곧")
    license!(soon.product, starts_on: Date.current + 3, last_usable_on: Date.current + 30)
    ended_earlier = series!("ended-earlier", name: "일찍 끝남")
    license!(ended_earlier.product, starts_on: Date.current - 90, last_usable_on: Date.current - 60)
    ended_later = series!("ended-later", name: "늦게 끝남")
    license!(ended_later.product, starts_on: Date.current - 40, last_usable_on: Date.current - 10)
    canceled = series!("canceled-only", name: "취소만")
    license!(canceled.product, starts_on: Date.current - 5, status: "canceled")
    sign_in
    get mypage_path
    assert_equal %w[newer older soon ended_later ended_earlier], codes("시리즈")
  end

  # HQ 0082 -- with a long title the badge stays on one line and doesn't shrink.
  test "card badges never wrap or shrink" do
    license!(series!("long-title", name: "아주 긴 시리즈 이름이 두 줄로 꺾이는 경우를 확인하기 위한 제목").product, starts_on: Date.current - 1)
    license!(@chatdox, starts_on: Date.current + 3, last_usable_on: Date.current + 30)
    sign_in
    get mypage_path
    badges = css_select("[data-license-card] span.rounded-full")
    assert_equal 2, badges.size
    badges.each { |b| assert_includes b["class"].split, "whitespace-nowrap"; assert_includes b["class"].split, "shrink-0" }
  end

  test "series a customer can't open: card without a link" do
    hidden = series!("hidden-line", name: "닫힌 시리즈", status: "draft")
    license!(hidden.product, starts_on: Date.current - 1)
    sign_in
    get mypage_path
    assert_equal "닫힌 시리즈", card("hidden_line").at_css("h4").text.strip
    assert_nil card("hidden_line").at_css("a")
  end

  # --- 0085 R2: records, not cards ---------------------------------------------------------------------

  test "each part is a divided list of one-line records (name, badge, period); no 콘텐츠 보기 anywhere" do
    line = series!("git-core", name: "Git의 기본")
    license!(line.product, starts_on: Date.new(2026, 6, 1), last_usable_on: Date.new(2026, 6, 30))
    license!(line.product, starts_on: Date.current - 1)
    license!(@chatdox, starts_on: Date.current - 5, last_usable_on: Date.current + 25)
    sign_in
    get mypage_path
    [ "시리즈", "이전 상품" ].each do |label|
      assert_select "section[aria-label='#{label}'] ul.divide-y > li[data-license-card]", 1, label
      assert_select "section[aria-label='#{label}'] .grid", 0, label
    end
    row = card("git_core").at_css("div")
    assert_equal [ "h4", "span", "p" ], row.element_children.map(&:name)
    assert_equal [ "Git의 기본", "이용 중", "무기한 이용 중" ], row.element_children.map { |e| e.text.strip }
    assert_equal "지난 기록 1건", card("git_core").at_css("details > summary").text.strip
    assert_not_includes css_select("section[aria-label='상품별 라이선스']").first.text, "콘텐츠 보기"
  end

  test "the 시리즈 empty line keeps its 시리즈 둘러보기 → link" do
    sign_in
    get mypage_path
    assert_select "section[aria-label='시리즈'] a[href=?]", products_path, text: "시리즈 둘러보기 →"
  end

  # --- page-level (0081) -------------------------------------------------------------------------------

  test "title, footer, no dashboard link, no purchase line" do
    @chatdox.update!(sale_enabled: true)
    sign_in
    get mypage_path
    assert_select "title", text: "마이페이지 | LEEDOX"
    assert_select "footer a[href=?]", announcements_path, text: "공지"
    assert_not_includes response.body, "진행률은 대시보드에서"
    section = css_select("section[aria-label='상품별 라이선스']").first
    assert_empty section.css("a").select { |a| a.text.strip.end_with?("구매") }
  end

  test "the order history (paid names, 환불 요청, 새 주문으로 재시도) is unchanged" do
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
    orders = css_select("li").select { |li| li.text.include?("주문번호") }
    paid_row = orders.find { |li| li.text.include?("결제 완료") }
    abandoned_row = orders.find { |li| li.text.include?("결제 이탈") }
    assert paid_row.text.include?("Claudox")
    assert paid_row.at_css("a[href='#{new_billing_order_refund_request_path(paid.public_id)}']"), "환불 요청 stays"
    assert abandoned_row.at_css("a[href='#{retry_billing_order_path(abandoned.public_id)}']"), "새 주문으로 재시도 stays"
    assert_equal [ "claudox" ], codes("이전 상품"), "the paid Claudox in use shows under 이전 상품"
  ensure
    ENV.delete("LEEDOX_COMMERCE_ENABLED")
  end

  # 0086: the pricing page is gone; the home's AI row is the way to the product page now.
  test "buying and extending stay reachable from the home and the product page (0081 R2)" do
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    @chatdox.update!(sale_enabled: true)
    license!(@chatdox, starts_on: Date.current - 5, last_usable_on: Date.current + 25)
    sign_in
    get root_path
    assert_select "section[aria-labelledby='track-ai'] a[href='/chatdox']"
    get "/chatdox"
    checkout = css_select("a").select { |a| a["href"].to_s.include?("checkout") }
    assert checkout.any?
    get checkout.first["href"]
    assert_response :success
    assert_includes response.body, (Date.current + 26).strftime("%Y-%m-%d")
  ensure
    ENV.delete("LEEDOX_COMMERCE_ENABLED")
  end

  test "guests are sent to sign in" do
    get mypage_path
    assert_redirected_to new_user_session_path
  end
end
