require "test_helper"

class ProductEntitlementAccessTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @user = User.create!(name: "테스트 유저", email: "reader@example.com", password: "password123", created_at: 30.days.ago)
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
  end

  test "Claudox index cannot use id parameter to bypass paid chapter policy" do
    get claudox_read_path, params: { id: "06" }

    assert_response :success
    assert_select "span", text: "잠금"
    assert_no_match(/낯선 오류 화면이 메일 한 통과 함께 도착했다/, response.body)
  end

  test "product license opens only its matching controller" do
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

    get doc_path("06")
    assert_response :success

    get claudox_chapter_path("06")
    # Logged-in users hitting a locked chapter land on that product's own
    # pricing section now, not the generic home redirect (handoff 0045 R2-4).
    assert_redirected_to "#{claudox_path}#pricing"
  end
end
