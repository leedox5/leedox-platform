require "test_helper"

# No prior coverage existed for this page -- added while fixing the
# "구독" column to show every product instead of only Chatdox (see
# leedox_admin_users_multi_product_subscription_r1).
class AdminUsersTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "admin-users-test@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: @admin.email, password: "password123" } }
  end

  test "the subscription column shows a badge per product, not just Chatdox" do
    user = User.create!(name: "테스트 유저", email: "admin-users-target@example.com", password: "password123")
    product = Product.find_by!(code: "claudox")
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    end_date = today + 1.month
    License.create!(
      user: user, product: product, source: "paid", status: "active",
      starts_on: today, last_usable_on: end_date - 1.day,
      access_ends_at: Commerce::PeriodCalculator::KST.local(end_date.year, end_date.month, end_date.day)
    )

    get admin_users_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    row = doc.css("tbody tr").find { |tr| tr.text.include?(user.email) }
    assert row, "expected a row for #{user.email}"

    assert_match(/Chatdox 미보유/, row.text)
    assert_match(/Claudox 이용 중/, row.text)
    assert_match(/AI, 오늘부터 시작 무료로 이용 가능/, row.text)
  end

  test "role update still works (regression -- this page's other function, untouched by this round)" do
    user = User.create!(name: "테스트 유저", email: "admin-users-role@example.com", password: "password123")

    patch admin_user_path(user), params: { user: { role: "admin" } }
    assert_redirected_to admin_users_path
    assert_equal "admin", user.reload.role
  end

  test "an admin still cannot demote their own account" do
    patch admin_user_path(@admin), params: { user: { role: "user" } }
    assert_redirected_to admin_users_path
    assert_equal "admin", @admin.reload.role
  end
end
