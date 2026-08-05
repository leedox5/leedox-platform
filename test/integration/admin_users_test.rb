require "test_helper"

class AdminUsersTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "admin-users-test@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: @admin.email, password: "password123" } }
  end

  test "구독 column shows a badge only for owned products, and folds the rest into one 미보유 line" do
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

    assert_match(/Claudox 이용 중/, row.text)
    # aistart (free_access) is excluded from this column entirely.
    assert_no_match(/AI, 오늘부터 시작/, row.text)
    # Everything the user doesn't hold collapses into one summary line
    # (products ordered by code: aigravity, chatdox, claudox).
    assert_match(/미보유: Antigravity 개발 실전, Chatdox/, row.text)
  end

  test "구독 column shows only the 미보유 summary when the user owns nothing" do
    user = User.create!(name: "빈 유저", email: "admin-users-empty@example.com", password: "password123")

    get admin_users_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    row = doc.css("tbody tr").find { |tr| tr.text.include?(user.email) }
    assert row, "expected a row for #{user.email}"

    assert_no_match(/이용 중/, row.text)
    assert_match(/미보유: Antigravity 개발 실전, Chatdox, Claudox/, row.text)
  end

  test "role update still works (regression -- untouched by this round)" do
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

  test "granting a free license issues a 12-month coupon license with no order_item" do
    user = User.create!(name: "테스트 유저", email: "admin-users-grant@example.com", password: "password123")
    product = Product.find_by!(code: "chatdox")

    assert_difference -> { user.licenses.count }, 1 do
      post grant_free_license_admin_user_path(user, product_code: product.code)
    end
    assert_redirected_to admin_users_path

    license = user.licenses.for_product("chatdox").last
    assert_equal "coupon", license.source
    assert_nil license.order_item_id
    assert_equal license.starts_on + 1.year - 1.day, license.last_usable_on
  end

  test "granting a free license records a commerce audit event" do
    user = User.create!(name: "테스트 유저", email: "admin-users-grant-audit@example.com", password: "password123")
    product = Product.find_by!(code: "claudox")

    assert_difference -> { CommerceAuditEvent.count }, 1 do
      post grant_free_license_admin_user_path(user, product_code: product.code)
    end

    event = CommerceAuditEvent.last
    assert_equal "free_license_granted", event.action
    assert_equal @admin, event.actor
    assert_equal user.licenses.for_product("claudox").last, event.auditable
  end

  test "granting a free license again on top of an existing one stacks instead of overlapping" do
    user = User.create!(name: "테스트 유저", email: "admin-users-grant-stack@example.com", password: "password123")
    product = Product.find_by!(code: "chatdox")
    post grant_free_license_admin_user_path(user, product_code: product.code)
    first_license = user.licenses.for_product("chatdox").last

    post grant_free_license_admin_user_path(user, product_code: product.code)
    second_license = user.licenses.for_product("chatdox").order(:starts_on).last

    assert_equal first_license.last_usable_on + 1.day, second_license.starts_on
  end

  test "aigravity is not offered as a free-grant button (not on sale yet)" do
    user = User.create!(name: "테스트 유저", email: "admin-users-no-aigravity@example.com", password: "password123")
    product = Product.find_by!(code: "aigravity")

    get admin_users_path
    assert_response :success
    assert_no_match(/#{Regexp.escape(product.name)} 1년 무료 부여/, response.body)

    assert_no_difference -> { user.licenses.count } do
      post grant_free_license_admin_user_path(user, product_code: product.code)
    end
    assert_redirected_to admin_users_path
  end

  test "a non-admin cannot grant a free license" do
    delete destroy_user_session_path
    user = User.create!(name: "일반 유저", email: "admin-users-nonadmin@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    target = User.create!(name: "대상 유저", email: "admin-users-grant-target@example.com", password: "password123")
    product = Product.find_by!(code: "chatdox")

    assert_no_difference -> { target.licenses.count } do
      post grant_free_license_admin_user_path(target, product_code: product.code)
    end
  end
end
