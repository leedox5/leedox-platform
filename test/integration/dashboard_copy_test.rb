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

  # The dashboard's own copy, without product data (a product's tagline is data the admin edits -- 0078 -- and
  # Chatdox's still says "커리큘럼"; that is out of this handoff's scope).
  def own_copy(node)
    copy = node.dup
    copy.css("p.leading-relaxed").each(&:remove)
    copy.text
  end

  test "title, header line and footer" do
    sign_in(@user)
    get dashboard_path
    assert_response :success
    assert_select "title", text: "대시보드 | LEEDOX"
    assert_includes css_select("main header").text, "My Dashboard"
    assert_includes css_select("main header").text, "보던 곳에서 이어서 보세요."
    assert_select "footer a[href=?]", announcements_path, text: "공지"
    assert_select "footer a[href=?]", terms_path
    assert_select "footer a[href=?]", privacy_path
  end

  test "an owned product's card: short badge and end date, chapters you can see, progress in reading words" do
    grant("chatdox", last_usable_on: Date.new(2026, 10, 23))
    ChapterProgress.create!(user: @user, product_code: "chatdox", chapter_id: "01", completed_at: Time.current)
    sign_in(@user)
    get dashboard_path
    card = section("Chatdox 현황")
    text = card.text.squish
    assert_equal "이용 중", card.at_css("span.rounded-full").text.strip
    assert_equal "이용 종료일: 2026년 10월 23일", card.at_css("h2 + span + p, div + p").text.strip
    assert_includes text, "볼 수 있는 챕터 20/20"
    assert_includes text, "진행률 5%"
    assert_includes text, "20개 중 1개 읽음"
    assert_includes text, "최근에 읽은 챕터"
    assert_includes text, "다음 챕터"
    assert card.css("a").any? { |a| a.text.strip == "이어서 보기" }
    assert_equal "Chatdox 진행률", card.at_css("[role=progressbar]")["aria-label"], "the screen-reader label keeps the name"
    assert_no_match OLD_TONE, own_copy(card)
  end

  test "an owned product with nothing read yet, and with everything read" do
    grant("chatdox")
    sign_in(@user)
    get dashboard_path
    text = section("Chatdox 현황").text.squish
    assert_includes text, "아직 읽은 챕터가 없습니다."
    assert_includes text, "첫 챕터 시작"

    chapters = ProductContent.for("chatdox").chapters.reject { |c| c[:kind] == :appendix }
    chapters.each { |c| ChapterProgress.create!(user: @user, product_code: "chatdox", chapter_id: c[:id], completed_at: Time.current) }
    get dashboard_path
    text = section("Chatdox 현황").text.squish
    assert_includes text, "모든 챕터를 읽었습니다."
    assert_includes text, "필요한 챕터를 다시 읽어 보세요."
    assert_includes text, "진행률 100%"
  end

  test "not-yet-seen cards: short badge, chapters you can see, product-page button with /pricing's wording, prices aside" do
    grant("chatdox")
    sign_in(@user)
    get dashboard_path
    seen = section("더 둘러보기")
    assert seen
    assert_includes seen.text, "더 둘러보기"
    assert_includes seen.text, "다른 이야기도 둘러보세요."
    assert_select "section[aria-label='더 둘러보기'] a[href=?]", products_path, text: "시리즈 둘러보기 →"

    claudox = seen.css("h3").find { |h| h.text.strip == "Claudox" }.ancestors("div.flex-col").first
    text = claudox.text.squish
    assert_equal "미보유", claudox.at_css("span.rounded-full").text.strip
    assert_match %r{볼 수 있는 챕터: \d+/20}, text
    assert_equal "이용 중인 라이선스가 없습니다", claudox.css("div.rounded-md p").last.text.strip
    links = claudox.css("a").map { |a| [ a.text.strip, a["href"] ] }
    assert_equal [ [ "자세히 보기", "/claudox" ], [ "가격 보기 →", pricing_path ] ], links
    assert_no_match OLD_TONE, own_copy(seen)
  end

  test "a member with nothing owned sees the new empty line and the not-yet-seen section" do
    sign_in(@user)
    get dashboard_path
    empty = section("이용 중인 콘텐츠 없음")
    assert empty
    assert_includes empty.text, "아직 이용 중인 콘텐츠가 없습니다."
    assert_includes empty.text, "아래에서 관심 있는 콘텐츠를 둘러보세요."
    assert section("더 둘러보기")
    assert_no_match OLD_TONE, own_copy(css_select("main").first)
  end

  test "during the trial the not-yet-seen card notes the trial range, without the product name repeated" do
    trial = User.create!(name: "체험", email: "dc-trial-#{SecureRandom.hex(3)}@example.com", password: "password123")
    sign_in(trial)
    get dashboard_path
    # 0084: found by its text -- its color changed with the dark dashboard (it was border-violet-100).
    banner = css_select("main p").find { |p| p.text.include?("무료 체험 D-") }
    assert banner, "the trial banner (unchanged copy)"
    assert_includes banner.text, "무료 체험 D-"
    seen = section("더 둘러보기")
    assert_match(%r{볼 수 있는 챕터: \d+/20 \(체험 중\)}, seen.text.squish)
    assert seen.css("span.rounded-full").all? { |badge| badge.text.strip == "미보유" }, "badges without the product name"
    assert_no_match OLD_TONE, own_copy(css_select("main").first)
  end

  test "after the trial ended the banner keeps its 가격 보기 link" do
    sign_in(@user.tap { |u| u.update!(created_at: 10.days.ago) })
    get dashboard_path
    banner = css_select("main p").find { |p| p.text.include?("무료 체험 기간이 끝났습니다.") } # 0084: by text, not color
    assert banner
    assert_includes banner.text, "무료 체험 기간이 끝났습니다."
    assert banner.at_css("a[href='#{pricing_path}']")
  end

  test "the CTA wording is the one /pricing uses (free products start, others take a closer look)" do
    view = ActionView::Base.empty
    view.extend(StandaloneProductsHelper)
    assert_equal "무료로 시작하기", view.standalone_product_cta_label(Product.find_by!(code: "aistart"))
    assert_equal "자세히 보기", view.standalone_product_cta_label(Product.find_by!(code: "claudox"))
    get pricing_path
    assert_select "a[href='/content/aistart']", text: "무료로 시작하기"
    assert_select "a[href='/claudox']", text: "자세히 보기"
  end

  test "an admin opening /dashboard gets the same member dashboard; the admin dashboard is untouched" do
    admin = User.create!(name: "관리자", email: "dc-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin, created_at: 30.days.ago)
    sign_in(admin)
    get dashboard_path
    assert_response :success
    assert_select "title", text: "대시보드 | LEEDOX"
    assert_includes css_select("main header").text, "보던 곳에서 이어서 보세요."
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
