require "test_helper"

class ManualBankTransferCheckoutTest < ActionDispatch::IntegrationTest
  ENV_KEYS = %w[
    LEEDOX_COMMERCE_ENABLED PAYMENT_PROVIDER
    PORTONE_API_SECRET PORTONE_STORE_ID PORTONE_CHANNEL_KEY PORTONE_KAKAOPAY_CHANNEL_KEY PORTONE_WEBHOOK_SECRET
    BANK_TRANSFER_ACCOUNT_INFO
  ].freeze

  setup do
    Commerce::CatalogBootstrap.call!
    @previous_env = ENV_KEYS.to_h { |key| [ key, ENV[key] ] }
    ENV_KEYS.each { |key| ENV.delete(key) }
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    ENV["BANK_TRANSFER_ACCOUNT_INFO"] = "카카오뱅크 3333-01-1234567 (예금주 리독스)"
    @product = Product.find_by!(code: "chatdox")
    @product.update!(sale_enabled: true)
    @admin = User.create!(name: "테스트 유저", email: "manual-admin@example.com", password: "password123", role: :admin)
    @buyer = User.create!(name: "테스트 유저", email: "manual-buyer@example.com", password: "password123", created_at: 30.days.ago)
  end

  teardown do
    @previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "PortOne unconfigured: full manual checkout to admin confirmation issues a license" do
    sign_in(@buyer)
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date

    get billing_checkout_path
    assert_response :success
    assert_no_match(/준비하고 있습니다/, response.body)
    assert_select "input[type='submit'][value=?]", "주문하기"

    assert_difference [ "Order.count", "OrderItem.count", "PaymentTransaction.count" ], 1 do
      post billing_orders_path, params: {
        order: { product_code: "chatdox", offer_code: "chatdox-1m-v1", requested_start_on: today }
      }
    end
    order = Order.order(:created_at).last
    assert_equal "manual", order.provider
    assert_equal "pending", order.status
    assert_redirected_to billing_order_path(order.public_id)

    follow_redirect!
    assert_response :success
    assert_select "script[src*='portone']", count: 0
    assert_select "#payment-button", count: 0
    assert_select "h1", text: /주문이 접수되었습니다/
    assert_match(/결제 대기 중/, response.body)
    assert_no_match(/주문 내용을 확인해 주세요/, response.body)
    assert_match(/카카오뱅크 3333-01-1234567/, response.body)
    assert_match(/24시간 이내 확인 후 라이선스가 발급됩니다/, response.body)
    reference = order.public_id.delete("-").first(8).upcase
    assert_match(Regexp.new(Regexp.escape(reference)), response.body)

    delete destroy_user_session_path
    sign_in(@admin)

    get admin_commerce_order_path(order.public_id)
    assert_response :success
    assert_match(Regexp.new(Regexp.escape(reference)), response.body)
    assert_select "form[action=?]", confirm_manual_payment_admin_commerce_order_path(order.public_id)

    assert_difference "License.count", 1 do
      post confirm_manual_payment_admin_commerce_order_path(order.public_id)
    end
    assert_redirected_to admin_commerce_order_path(order.public_id)

    order.reload
    assert_equal "paid", order.status
    assert order.licenses.exists?
    assert_equal 1, PaymentTransaction.where(purchase_order: order).count
    assert_equal "active", order.payment_transaction.reload.status

    audit = order.commerce_audit_events.find_by(action: "manual_payment_confirmed")
    assert audit, "expected a manual_payment_confirmed audit event"
    assert_equal @admin, audit.actor
    assert_equal "pending", audit.from_state
    assert_equal "paid", audit.to_state
  end

  test "confirming twice or a non-pending order is rejected without side effects" do
    order = create_manual_order(@buyer)
    sign_in(@admin)

    post confirm_manual_payment_admin_commerce_order_path(order.public_id)
    assert_equal "paid", order.reload.status

    assert_no_difference [ "License.count", "PaymentTransaction.count", "CommerceAuditEvent.count" ] do
      post confirm_manual_payment_admin_commerce_order_path(order.public_id)
    end
    assert_redirected_to admin_commerce_order_path(order.public_id)
    assert_equal "무통장입금 대기 중인 주문만 확인할 수 있습니다.", flash[:alert]
  end

  test "confirming a portone order is rejected -- the action is manual-only" do
    ENV.update(
      "PAYMENT_PROVIDER" => "portone",
      "PORTONE_API_SECRET" => "test-api-secret",
      "PORTONE_STORE_ID" => "test-store-id",
      "PORTONE_CHANNEL_KEY" => "test-channel-key",
      "PORTONE_WEBHOOK_SECRET" => "test-portone-webhook-secret"
    )
    order = Commerce::OrderCreator.call!(
      user: @buyer,
      product_code: "chatdox",
      offer_code: "chatdox-1m-v1",
      requested_start_on: Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date,
      provider: "portone"
    )
    sign_in(@admin)

    assert_no_difference [ "License.count", "CommerceAuditEvent.count" ] do
      post confirm_manual_payment_admin_commerce_order_path(order.public_id)
    end
    assert_equal "pending", order.reload.status
  end

  test "non-admins cannot confirm manual payments" do
    order = create_manual_order(@buyer)

    post confirm_manual_payment_admin_commerce_order_path(order.public_id)
    assert_redirected_to new_user_session_path

    sign_in(@buyer)
    post confirm_manual_payment_admin_commerce_order_path(order.public_id)
    assert_redirected_to root_path
    assert_equal "pending", order.reload.status
  end

  test "PortOne fully configured: checkout uses portone, not manual, and card widget is shown" do
    ENV.update(
      "PAYMENT_PROVIDER" => "portone",
      "PORTONE_API_SECRET" => "test-api-secret",
      "PORTONE_STORE_ID" => "test-store-id",
      "PORTONE_CHANNEL_KEY" => "test-channel-key",
      "PORTONE_KAKAOPAY_CHANNEL_KEY" => "test-kakaopay-channel-key",
      "PORTONE_WEBHOOK_SECRET" => "test-portone-webhook-secret"
    )
    sign_in(@buyer)
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date

    post billing_orders_path, params: {
      order: { product_code: "chatdox", offer_code: "chatdox-1m-v1", requested_start_on: today }
    }
    order = Order.order(:created_at).last
    assert_equal "portone", order.provider

    follow_redirect!
    assert_response :success
    assert_select "script[src*='portone']"
    assert_select "#payment-button"
    assert_select "h1", text: "주문 내용을 확인해 주세요"
    assert_no_match(/무통장입금 안내/, response.body)
    assert_no_match(/결제 대기 중/, response.body)
  end

  test "landing page and my page purchase links stay open without PortOne configured" do
    get chatdox_path
    assert_response :success
    assert_no_match(/준비 중이며 현재는 구매할 수 없습니다/, response.body)
    assert_select "a[href=?]", billing_checkout_path, text: /기간제 라이선스 구매/

    sign_in(@buyer)
    get mypage_path
    assert_response :success
    assert_select "a[href=?]", billing_checkout_path, text: "Chatdox 구매"
  end

  private

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def create_manual_order(user)
    Commerce::OrderCreator.call!(
      user: user,
      product_code: "chatdox",
      offer_code: "chatdox-1m-v1",
      requested_start_on: Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date,
      provider: "manual"
    )
  end
end
