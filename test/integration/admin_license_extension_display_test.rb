require "test_helper"

class AdminLicenseExtensionDisplayTest < ActionDispatch::IntegrationTest
  KST = ActiveSupport::TimeZone["Asia/Seoul"]

  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "admin-ext@example.com", password: "password123", role: :admin)
    @user = User.create!(name: "일반유저", email: "user-ext@example.com", password: "password123", role: :user)
    @chatdox = Product.find_by!(code: "chatdox")
    @claudox = Product.find_by!(code: "claudox")
  end

  test "1 & 2. Free grant stacks separate records without overlap and displays contiguous chain in admin user management" do
    login_as(@admin)

    # Setup active license: 2026.08.06 ~ 2026.09.05
    start_date = Date.new(2026, 8, 6)
    last_usable = Date.new(2026, 9, 5)
    access_ends = KST.local(2026, 9, 6)

    initial_license = License.create!(
      user: @user,
      product: @chatdox,
      source: "paid",
      status: "active",
      starts_on: start_date,
      last_usable_on: last_usable,
      access_ends_at: access_ends
    )

    # Grant 1 year free license via admin endpoint
    assert_difference "License.count", 1 do
      post grant_free_license_admin_user_path(@user, product_code: "chatdox")
    end

    new_license = License.order(:created_at).last
    assert_equal "coupon", new_license.source
    assert_equal "scheduled", new_license.status
    assert_equal Date.new(2026, 9, 6), new_license.starts_on
    assert_equal Date.new(2027, 9, 5), new_license.last_usable_on

    # DB records do not overlap
    assert_equal initial_license.access_ends_at, new_license.starts_at

    # Admin user management displays contiguous chain: 2026.08.06 ~ 2027.09.05
    get admin_users_path
    assert_response :success
    assert_select "tr" do |rows|
      user_row = rows.find { |r| r.text.include?("일반유저") }
      assert user_row, "User row must be present"
      assert_includes user_row.text, "Chatdox 이용 중"
      assert_includes user_row.text, "2026.08.06 ~ 2027.09.05"
    end
  end

  test "3. Both Chatdox and Claudox support contiguous license period display and stacking" do
    login_as(@admin)

    [ @chatdox, @claudox ].each do |product|
      user = User.create!(name: "#{product.name} 유저", email: "#{product.code}-chain@example.com", password: "password123")

      License.create!(
        user: user,
        product: product,
        source: "paid",
        status: "active",
        starts_on: Date.new(2026, 8, 6),
        last_usable_on: Date.new(2026, 9, 5),
        access_ends_at: KST.local(2026, 9, 6)
      )

      post grant_free_license_admin_user_path(user, product_code: product.code)
      assert_redirected_to admin_users_path

      get admin_users_path
      assert_response :success
      assert_select "tr" do |rows|
        user_row = rows.find { |r| r.text.include?(user.name) }
        assert user_row, "User row for #{user.name} must be present"
        assert_includes user_row.text, "#{product.name} 이용 중"
        assert_includes user_row.text, "2026.08.06 ~ 2027.09.05"
      end
    end
  end

  test "4. Scheduled-only user is displayed with '이용 예정' badge and period, not as '미보유'" do
    login_as(@admin)

    # Scheduled license starting in future
    License.create!(
      user: @user,
      product: @chatdox,
      source: "coupon",
      status: "scheduled",
      starts_on: Date.new(2026, 9, 6),
      last_usable_on: Date.new(2027, 9, 5),
      access_ends_at: KST.local(2027, 9, 6)
    )

    get admin_users_path
    assert_response :success

    # Badge shows 이용 예정 and period is displayed
    assert_select "tr" do |rows|
      user_row = rows.find { |r| r.text.include?("일반유저") }
      assert user_row, "User row must be present"
      assert_includes user_row.text, "Chatdox 이용 예정"
      assert_includes user_row.text, "2026.09.06 ~ 2027.09.05"
      refute_includes user_row.text, "미보유: Chatdox"
    end

    # Customer content access remains blocked for scheduled-only user
    login_as(@user)
    assert_not @user.licensed_for?("chatdox")
    get product_chapter_path("chatdox", "06")
    assert_redirected_to root_path
  end

  test "5. Canceled, expired, or discontiguous licenses with gaps are not incorrectly merged" do
    login_as(@admin)

    # Active license: 2026.08.06 ~ 2026.09.05
    License.create!(
      user: @user,
      product: @chatdox,
      source: "paid",
      status: "active",
      starts_on: Date.new(2026, 8, 6),
      last_usable_on: Date.new(2026, 9, 5),
      access_ends_at: KST.local(2026, 9, 6)
    )

    # Discontiguous scheduled license with gap: starts 2026.10.01 (25 days gap)
    License.create!(
      user: @user,
      product: @chatdox,
      source: "coupon",
      status: "scheduled",
      starts_on: Date.new(2026, 10, 1),
      last_usable_on: Date.new(2027, 9, 30),
      access_ends_at: KST.local(2027, 10, 1)
    )

    # Canceled license
    License.create!(
      user: @user,
      product: @chatdox,
      source: "paid",
      status: "canceled",
      starts_on: Date.new(2026, 9, 6),
      last_usable_on: Date.new(2026, 9, 30),
      access_ends_at: KST.local(2026, 10, 1)
    )

    get admin_users_path
    assert_response :success

    # Displays contiguous chain up to gap (2026.08.06 ~ 2026.09.05) and does not bridge across 25-day gap
    assert_select "tr" do |rows|
      user_row = rows.find { |r| r.text.include?("일반유저") }
      assert user_row, "User row must be present"
      assert_includes user_row.text, "2026.08.06 ~ 2026.09.05"
    end
  end

  test "6. Confirmation message and completion notice include current end date, added period, and final end date" do
    login_as(@admin)

    # Create initial active license: 2026.08.06 ~ 2026.09.05
    License.create!(
      user: @user,
      product: @chatdox,
      source: "paid",
      status: "active",
      starts_on: Date.new(2026, 8, 6),
      last_usable_on: Date.new(2026, 9, 5),
      access_ends_at: KST.local(2026, 9, 6)
    )

    get admin_users_path
    assert_response :success

    # Check button turbo_confirm data attribute
    assert_select "button[data-turbo-confirm*='현재 종료일: 2026.09.05']"
    assert_select "button[data-turbo-confirm*='추가 기간: 2026.09.06 ~ 2027.09.05']"
    assert_select "button[data-turbo-confirm*='최종 종료일: 2027.09.05']"

    # Grant free license and verify completion notice
    post grant_free_license_admin_user_path(@user, product_code: "chatdox")
    assert_redirected_to admin_users_path
    follow_redirect!

    assert_select "div", text: /부여 기간: 2026\.09\.06 ~ 2027\.09\.05/
    assert_select "div", text: /최종 종료일: 2027\.09\.05/
  end

  test "7. Non-regression of double-click stacking, authorization, audit events, and non-grantable products" do
    # Non-admin cannot grant free license
    login_as(@user)
    assert_no_difference -> { @user.licenses.count } do
      post grant_free_license_admin_user_path(@user, product_code: "chatdox")
    end
    assert_redirected_to root_path

    login_as(@admin)

    # Cannot grant for non-grantable product (e.g., aistart or non-existent)
    post grant_free_license_admin_user_path(@user, product_code: "aistart")
    assert_redirected_to admin_users_path
    follow_redirect!
    assert_select "div", text: /무료 부여할 수 없는 상품입니다/

    # Audit event recorded for free grant
    assert_difference "CommerceAuditEvent.count", 1 do
      post grant_free_license_admin_user_path(@user, product_code: "chatdox")
    end

    audit = CommerceAuditEvent.order(:created_at).last
    assert_equal "free_license_granted", audit.action
    assert_equal @admin.id, audit.actor_id
    assert_equal "admin_free_grant", audit.reason_code
  end

  private

  def login_as(user)
    delete destroy_user_session_path rescue nil
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
