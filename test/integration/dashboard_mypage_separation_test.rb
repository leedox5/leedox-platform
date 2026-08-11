require "test_helper"

class DashboardMypageSeparationTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @user = User.create!(name: "테스트 유저", email: "dashboard-mypage-separation@example.com", password: "password123")
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
  end

  test "dashboard is a learning hub: progress, recent chapters, next step, GitHub Lab, doc access -- no order/license ledger" do
    product = Product.find_by!(code: "chatdox")
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    end_date = today + 1.month
    License.create!(
      user: @user,
      product: product,
      source: "paid",
      status: "active",
      starts_on: today,
      last_usable_on: end_date - 1.day,
      access_ends_at: Commerce::PeriodCalculator::KST.local(end_date.year, end_date.month, end_date.day)
    )

    get dashboard_path
    assert_response :success

    assert_match(/학습 진도/, response.body)
    assert_match(/최근 완료한 챕터/, response.body)
    assert_match(/Next Step/, response.body)
    assert_no_match(/GitHub Lab/, response.body)
    assert_match(/접근 가능 문서/, response.body)

    assert_no_match(/상품별 라이선스/, response.body)
    assert_select "[aria-label='상품별 라이선스']", count: 0
    assert_select "a[href=?]", mypage_path, text: /마이페이지/
  end

  test "dashboard shows multi-product status and doc access (R2: Chatdox + Claudox, not Chatdox-only)" do
    get dashboard_path
    assert_response :success

    assert_match(/Chatdox/, response.body)
    assert_match(/Claudox/, response.body)

    assert_no_match(/전체 문서 보기/, response.body)
    assert_no_match(/계정 역할/, response.body)
  end

  test "my page owns account info and the full order/license ledger -- no learning-progress mini block" do
    get mypage_path
    assert_response :success

    assert_match(/계정 정보/, response.body)
    assert_select "[aria-label='상품별 라이선스']"

    assert_no_match(/학습 요약/, response.body)
    assert_no_match(/완료한 챕터/, response.body)
    assert_select "a[href=?]", dashboard_path, text: /대시보드/
    assert_select "title", text: /마이페이지 - LEEDOX/

    get edit_user_registration_path
    assert_response :success
    assert_select "title", text: /내 정보 수정 - LEEDOX/
    assert_match(/새 비밀번호는 10자 이상/, response.body)
  end

  test "trial remaining days shown on dashboard, not on my page (R2: 이용 상태 card removed from my page)" do
    @user.update!(created_at: 1.day.ago)
    assert @user.trial_active?, "expected a fresh user to be in an active trial"

    get dashboard_path
    assert_response :success
    assert_match(/무료 체험/, response.body)

    get mypage_path
    assert_response :success
    assert_no_match(/이용 상태/, response.body)
    assert_no_match(/Trial 남은 기간/, response.body)
  end

  test "a Claudox-licensed user sees Claudox marked as licensed and full Claudox chapter access, while Chatdox stays trial-only" do
    product = Product.find_by!(code: "claudox")
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    end_date = today + 1.month
    License.create!(
      user: @user,
      product: product,
      source: "paid",
      status: "active",
      starts_on: today,
      last_usable_on: end_date - 1.day,
      access_ends_at: Commerce::PeriodCalculator::KST.local(end_date.year, end_date.month, end_date.day)
    )

    get dashboard_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    claudox_section = doc.at_css("section[aria-label='Claudox 현황']").text
    catalog_section = doc.at_css("section[aria-label='전체 카탈로그 둘러보기']").text

    assert_match(/Claudox 이용 중/, claudox_section)
    assert_match(%r{20/20}, claudox_section)
    assert_match(/Chatdox 미보유/, catalog_section)
    assert_match(%r{5/20}, catalog_section)
  end

  test "mobile navigation includes 대시보드 for a regular signed-in user, matching desktop" do
    get root_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    desktop_labels = doc.css("header nav[aria-label='주요 내비게이션'] a").map(&:text)
    mobile_labels = doc.css("nav[aria-label='모바일 내비게이션'] a").map(&:text)

    assert_includes desktop_labels, "대시보드"
    assert_includes mobile_labels, "대시보드"
    assert_equal desktop_labels, mobile_labels
  end
end
