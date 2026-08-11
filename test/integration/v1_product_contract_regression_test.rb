require "test_helper"

class V1ProductContractRegressionTest < ActionDispatch::IntegrationTest
  KST = Commerce::PeriodCalculator::KST

  setup do
    Commerce::CatalogBootstrap.call!
    @chatdox = Product.find_by!(code: "chatdox")
    @claudox = Product.find_by!(code: "claudox")
    @user = User.create!(name: "계약 테스트 유저", email: "v1-contract@example.com", password: "password123", created_at: 30.days.ago)
    @admin = User.create!(name: "관리자 유저", email: "v1-admin@example.com", password: "password123", role: :admin)
  end

  test "1. Chatdox and Claudox landing, pricing, and terms pages match QA/03 V1 product promises and lack unpromised benefits" do
    # Terms page (/terms)
    get terms_path
    assert_response :success
    terms_body = response.body
    assert_match(/Chatdox 핵심 웹 챕터 20개 및 라이선스 기간 중 신규 웹 콘텐츠/, terms_body)
    assert_match(/Claudox 핵심 웹 챕터 20개, 라이선스 전용 특별판 및 신규 챕터/, terms_body)
    assert_no_match(/소스코드 전체.*포함\(수동 초대\)/, terms_body)
    assert_no_match(/GitHub 비공개 저장소\(Lab\) 접근/, terms_body)

    # Chatdox landing page (/chatdox)
    get chatdox_path
    assert_response :success
    chatdox_body = response.body
    assert_match(/20개 실전 웹 챕터, 단계별 코드 예제/, chatdox_body)
    assert_match(/코드 예제 및 설명/, chatdox_body)
    assert_match(/문의 채널/, chatdox_body)
    assert_no_match(/GitHub 템플릿 코드/, chatdox_body)
    assert_no_match(/48시간 이내 이메일 지원/, chatdox_body)

    # Claudox landing page (/claudox)
    get claudox_path
    assert_response :success
    claudox_body = response.body
    assert_match(/Claudox 챕터 텍스트 20장/, claudox_body)
    assert_match(/읽기 경로와 적용 힌트, 실제 협업 사례 맥락/, claudox_body)

    # Pricing page (/pricing) - summary page
    get pricing_path
    assert_response :success
    pricing_body = response.body
    assert_match(/Chatdox/, pricing_body)
    assert_match(/Claudox/, pricing_body)
    assert_match(/최저 7,700원부터/, pricing_body)
    assert_match(/최저 3,850원부터/, pricing_body)

    # Chatdox pricing section (/chatdox)
    assert_match(/자동 갱신 없는 기간제 선불 라이선스/, chatdox_body)
    assert_match(/VAT가 포함된 실제 결제 예정 금액/, chatdox_body)
    assert_match(/1개월/, chatdox_body)
    assert_match(/3개월/, chatdox_body)
    assert_match(/6개월/, chatdox_body)
    assert_match(/12개월/, chatdox_body)

    # Claudox pricing section (/claudox)
    assert_match(/자동 갱신 없는 기간제 선불 라이선스/, claudox_body)
    assert_match(/VAT가 포함된 실제 결제 예정 금액/, claudox_body)
    assert_match(/1개월/, claudox_body)
    assert_match(/3개월/, claudox_body)
    assert_match(/6개월/, claudox_body)
    assert_match(/12개월/, claudox_body)
  end

  test "2. Active license grants paid web content access for its matching product only" do
    create_active_license(user: @user, product: @chatdox)
    sign_in(@user)

    # Chatdox active license -> Chatdox paid chapter 06 accessible
    get product_chapter_path("chatdox", "06")
    assert_response :success

    # Chatdox active license -> Claudox paid chapter 06 blocked, redirected to
    # Claudox's own pricing section (handoff 0045 R2-4), not the generic home page.
    get product_chapter_path("claudox", "06")
    assert_redirected_to "#{claudox_path}#pricing"
  end

  test "2-b. Active Claudox license grants Claudox paid web content access only" do
    create_active_license(user: @user, product: @claudox)
    sign_in(@user)

    # Claudox active license -> Claudox paid chapter 06 accessible
    get product_chapter_path("claudox", "06")
    assert_response :success

    # Claudox active license -> Chatdox paid chapter 06 blocked, redirected to
    # Chatdox's own pricing section (handoff 0045 R2-4), not the generic home page.
    get product_chapter_path("chatdox", "06")
    assert_redirected_to "#{chatdox_path}#pricing"
  end

  test "3. Scheduled, expired, and canceled licenses do not grant paid web content access" do
    sign_in(@user)

    # Logged-in users hitting a locked chapter land on that product's own
    # pricing section now, not the generic home redirect (handoff 0045 R2-4).

    # Scheduled license (future)
    scheduled = create_scheduled_license(user: @user, product: @chatdox)
    get product_chapter_path("chatdox", "06")
    assert_redirected_to "#{chatdox_path}#pricing"
    scheduled.destroy

    # Expired license (past)
    expired = create_expired_license(user: @user, product: @chatdox)
    get product_chapter_path("chatdox", "06")
    assert_redirected_to "#{chatdox_path}#pricing"
    expired.destroy

    # Canceled license
    canceled = create_canceled_license(user: @user, product: @chatdox)
    get product_chapter_path("chatdox", "06")
    assert_redirected_to "#{chatdox_path}#pricing"
  end

  test "4. GitHub Lab UI entry points and routes are completely disabled in V1" do
    # Customer dashboard & route
    sign_in(@user)
    get dashboard_path
    assert_response :success
    assert_select "a[href=?]", github_access_path, count: 0
    assert_no_match(/Chatdox GitHub Lab/, response.body)

    get github_access_path
    assert_redirected_to dashboard_path
    assert_equal "GitHub Lab 연결 기능은 현재 V1 제공 범위에 포함되지 않습니다.", flash[:alert]

    # Admin dashboard & routes
    delete destroy_user_session_path
    sign_in(@admin)
    get admin_dashboard_path
    assert_response :success
    assert_select "a[href=?]", admin_commerce_github_access_path, count: 0

    get admin_commerce_github_access_path
    assert_redirected_to admin_dashboard_path
    assert_equal "GitHub Lab 운영 기능은 현재 V1 제공 범위에 포함되지 않습니다.", flash[:alert]
  end

  test "5. Unauthenticated user accessing checkout is redirected to sign-in and returns to checkout" do
    begin
      old_env = ENV["LEEDOX_COMMERCE_ENABLED"]
      ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
      @chatdox.update!(sale_enabled: true)
      @claudox.update!(sale_enabled: true)

      # Chatdox checkout flow
      get billing_checkout_path("chatdox")
      assert_redirected_to new_user_session_path

      post user_session_path, params: { user: { email: @user.email, password: "password123" } }
      assert_redirected_to billing_checkout_path("chatdox")

      delete destroy_user_session_path

      # Claudox checkout flow
      get billing_checkout_path("claudox")
      assert_redirected_to new_user_session_path

      post user_session_path, params: { user: { email: @user.email, password: "password123" } }
      assert_redirected_to billing_checkout_path("claudox")
    ensure
      ENV["LEEDOX_COMMERCE_ENABLED"] = old_env
    end
  end

  test "6. Free introductory product (aistart) is accessible to guests without a license" do
    get product_content_index_path("aistart")
    assert_response :success

    get product_chapter_path("aistart", "01")
    assert_response :success
    assert_match(/오늘, 누군가를 처음 만났다/, response.body)
  end

  private

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def create_active_license(user:, product:)
    today = Time.current.in_time_zone(KST).to_date
    end_date = today + 1.month
    License.create!(
      user: user, product: product, source: "paid", status: "active",
      starts_on: today, last_usable_on: end_date - 1.day,
      access_ends_at: KST.local(end_date.year, end_date.month, end_date.day)
    )
  end

  def create_scheduled_license(user:, product:)
    today = Time.current.in_time_zone(KST).to_date
    start_on = today + 5.days
    end_date = start_on + 1.month
    License.create!(
      user: user, product: product, source: "paid", status: "scheduled",
      starts_on: start_on, last_usable_on: end_date - 1.day,
      access_ends_at: KST.local(end_date.year, end_date.month, end_date.day)
    )
  end

  def create_expired_license(user:, product:)
    today = Time.current.in_time_zone(KST).to_date
    start_on = today - 2.months
    last_on = start_on + 1.month - 1.day
    License.create!(
      user: user, product: product, source: "paid", status: "active",
      starts_on: start_on, last_usable_on: last_on,
      access_ends_at: KST.local((last_on + 1.day).year, (last_on + 1.day).month, (last_on + 1.day).day)
    )
  end

  def create_canceled_license(user:, product:)
    today = Time.current.in_time_zone(KST).to_date
    end_date = today + 1.month
    License.create!(
      user: user, product: product, source: "paid", status: "canceled",
      starts_on: today, last_usable_on: end_date - 1.day,
      access_ends_at: KST.local(end_date.year, end_date.month, end_date.day)
    )
  end
end
