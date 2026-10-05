require "test_helper"

# Handoff 0079 -- the member dashboard's copy in the story-series tone, no internal note, no product name
# repeated under a card title, a product-page button (with /pricing's wording) on not-yet-seen cards,
# a link to the series, the common footer and a page title. Which products show and the owned/trial/
# expired judgments are unchanged (covered by the existing dashboard tests).
class DashboardCopyTest < ActionDispatch::IntegrationTest
  OLD_TONE = /학습|커리큘럼|스킬|수강|강의|카탈로그|복습|접근 가능 문서|Next Step|실제 문서 접근은/

  setup do
    Commerce::CatalogBootstrap.call!
    @user = User.create!(name: "회원", email: "dc-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def grant(code, last_usable_on: Date.current + 19.days)
    License.create!(user: @user, product: Product.find_by!(code: code), source: "paid", status: "active",
      starts_on: Date.current, last_usable_on: last_usable_on,
      access_ends_at: Time.zone.local((last_usable_on + 1).year, (last_usable_on + 1).month, (last_usable_on + 1).day))
  end

  def section(label) = css_select("section[aria-label='#{label}']").first

  # Handoff 0085 -- 더 둘러보기 lists series not in use, so the tests that look at it need one.
  def series!(slug, name: "시리즈 #{slug}", summary: nil)
    line = ProductLine.create!(internal_name: slug, customer_name: name, slug: slug, introduction: "소개", summary: summary,
      status: "published", visibility: "public")
    line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문", status: "published")
    line
  end

  # The dashboard's own copy, without product data (a product's tagline is data the admin edits -- 0078 -- and
  # Chatdox's still says "커리큘럼"; that is out of this handoff's scope).
  def own_copy(node)
    copy = node.dup
    copy.css("p.leading-relaxed").each(&:remove)
    copy.text
  end

  # Handoff 0089 -- no header block any more (eyebrow, greeting, "보던 곳에서 이어서 보세요.", my page link).
  test "title, no header block, one heading with the name, and footer" do
    sign_in(@user)
    get dashboard_path
    assert_response :success
    assert_select "title", text: "대시보드 | LEEDOX"
    assert_select "main header", 0
    assert_select "h1", count: 1, text: "회원님이 이용 중인 콘텐츠"
    text = css_select("main").first.text
    [ "My Dashboard", "안녕하세요", "보던 곳에서 이어서 보세요.", "결제·라이선스 내역은 마이페이지에서" ].each { |gone| assert_not_includes text, gone }
    assert_select "footer a[href=?]", announcements_path, text: "공지"
    assert_select "footer a[href=?]", terms_path
    assert_select "footer a[href=?]", privacy_path
  end

  # Handoff 0089 -- an earlier product's card is the name, 이용 중 and its end date, and the whole card links to the
  # product's contents; chapter counts, progress, recent and next chapters are gone (reading records still kept).
  test "an owned product's card: name, 이용 중 and end date, the whole card linking to its contents" do
    grant("chatdox", last_usable_on: Date.new(2026, 10, 23))
    ChapterProgress.create!(user: @user, product_code: "chatdox", chapter_id: "01", completed_at: Time.current)
    sign_in(@user)
    get dashboard_path
    card = section("Chatdox 현황")
    link = card.at_css("a")
    assert_equal product_content_index_path("chatdox"), link["href"]
    assert_equal 1, card.css("a").size, "one link: the card itself"
    assert_equal "Chatdox 이용 중 이용 종료일: 2026년 10월 23일", link.text.squish
    [ "볼 수 있는 챕터", "진행률", "개 중", "최근에 읽은 챕터", "다음 챕터", "이어서 보기", "첫 챕터 시작", "다시 보기", "전체 보기" ].each do |gone|
      assert_not_includes card.text, gone
    end
    assert_nil card.at_css("[role=progressbar]")
    assert_no_match OLD_TONE, own_copy(card)
  end

  # Handoff 0085 R1 -- the lower section shows series (the /products card), no earlier product (no 미보유 card, no
  # 가격 보기 →). Handoff 0089 -- it's called 다른 콘텐츠, without the line under it or a 시리즈 둘러보기 link.
  test "not-yet-seen cards are series: the series list's card, no earlier product, no prices link" do
    grant("chatdox")
    series!("copy-line", name: "이야기 시리즈", summary: "한 줄 요약")
    sign_in(@user)
    get dashboard_path
    seen = section("다른 콘텐츠")
    assert seen
    assert_equal "다른 콘텐츠", seen.at_css("h2").text.strip
    assert_not_includes seen.text, "다른 이야기도 둘러보세요."
    assert_select "main a", text: "시리즈 둘러보기 →", count: 0

    card = seen.at_css("a[href='#{product_line_path("copy-line")}']")
    text = card.text.squish
    assert_equal "이야기 시리즈", card.at_css("h3").text.strip
    assert_includes text, "한 줄 요약"
    assert_includes text, "공개 1편"
    assert_includes text, "자세히 보기 →"
    assert_not_includes seen.text, "Claudox"
    assert_not_includes seen.text, "가격 보기"
    assert_no_match OLD_TONE, own_copy(seen)
  end

  test "a member with nothing owned sees the new empty line and the not-yet-seen section" do
    series!("copy-line")
    sign_in(@user)
    get dashboard_path
    empty = section("이용 중인 콘텐츠 없음")
    assert empty
    assert_includes empty.text, "아직 이용 중인 콘텐츠가 없습니다."
    assert_includes empty.text, "아래에서 관심 있는 콘텐츠를 둘러보세요."
    assert section("다른 콘텐츠")
    assert_no_match OLD_TONE, own_copy(css_select("main").first)
  end

  # Handoff 0086 -- the trial banners (D-N, and "ended" with its 가격 보기 link) are gone with the pricing page, and
  # the card CTA wording went with it (pricing_removal_test.rb covers both banners and the trial's chapter access).
  test "during the trial the dashboard has no banner and no earlier-product trial line" do
    trial = User.create!(name: "체험", email: "dc-trial-#{SecureRandom.hex(3)}@example.com", password: "password123")
    sign_in(trial)
    get dashboard_path
    assert_not_includes css_select("main").text, "무료 체험"
    assert_not_includes css_select("main").text, "(체험 중)"
    assert_no_match OLD_TONE, own_copy(css_select("main").first)
  end

  test "an admin opening /dashboard gets the same member dashboard; the admin dashboard is untouched" do
    admin = User.create!(name: "관리자", email: "dc-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin, created_at: 30.days.ago)
    sign_in(admin)
    get dashboard_path
    assert_response :success
    assert_select "title", text: "대시보드 | LEEDOX"
    assert_select "h1", text: "관리자님이 이용 중인 콘텐츠" # 0089: the member heading (was the greeting block)
    get admin_dashboard_path
    assert_response :success
  end

  # 0079 renamed the my page link to "진행률은 대시보드에서 →"; 0081 R2 removed it (the header menu has 대시보드).
  test "the my page no longer links to the dashboard from the account card" do
    sign_in(@user)
    get mypage_path
    assert_not_includes response.body, "진행률은 대시보드에서"
    assert_not_includes response.body, "학습 진도는 대시보드에서"
  end

  test "guests are sent to sign in" do
    get dashboard_path
    assert_redirected_to new_user_session_path
  end
end
