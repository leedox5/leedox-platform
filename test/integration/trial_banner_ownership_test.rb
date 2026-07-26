require "test_helper"

class TrialBannerOwnershipTest < ActionDispatch::IntegrationTest
  BANNER_TEXT = "보유하지 않은 상품도 앞부분 챕터를 무료로 볼 수 있습니다"

  setup do
    Commerce::CatalogBootstrap.call!
  end

  def create_active_license(user, product_code)
    product = Product.find_by!(code: product_code)
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    end_date = today + 1.month
    License.create!(
      user: user, product: product, source: "paid", status: "active",
      starts_on: today, last_usable_on: end_date - 1.day,
      access_ends_at: Commerce::PeriodCalculator::KST.local(end_date.year, end_date.month, end_date.day)
    )
  end

  test "Trial user who owns nothing still sees the banner" do
    user = User.create!(name: "테스트 유저", email: "trial-banner-none@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    assert user.trial_active?

    get dashboard_path
    assert_response :success
    assert_match(/#{BANNER_TEXT}/, response.body)
  end

  test "Trial user who owns only some products still sees the banner" do
    user = User.create!(name: "테스트 유저", email: "trial-banner-partial@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    create_active_license(user, "chatdox")
    assert user.trial_active?
    assert_not Product.order(:code).all? { |p| user.licensed_for?(p.code) },
      "fixture assumption broken: user must not own every product yet"

    get dashboard_path
    assert_response :success
    assert_match(/#{BANNER_TEXT}/, response.body)
  end

  test "Trial user who owns every product on sale no longer sees the banner" do
    user = User.create!(name: "테스트 유저", email: "trial-banner-full@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    Product.order(:code).each { |product| create_active_license(user, product.code) }
    assert user.trial_active?

    get dashboard_path
    assert_response :success
    assert_no_match(/#{BANNER_TEXT}/, response.body)
  end

  test "user whose Trial has ended never sees the banner, regardless of ownership" do
    user = User.create!(name: "테스트 유저", email: "trial-banner-expired@example.com", password: "password123", created_at: 30.days.ago)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    assert_not user.trial_active?

    get dashboard_path
    assert_response :success
    assert_no_match(/#{BANNER_TEXT}/, response.body)
  end
end
