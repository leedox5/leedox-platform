require "test_helper"

class CommerceCheckoutTest < ActionDispatch::IntegrationTest
  PAYMENT_ENV_KEYS = %w[
    LEEDOX_COMMERCE_ENABLED PAYMENT_PROVIDER
    PORTONE_API_SECRET PORTONE_STORE_ID PORTONE_CHANNEL_KEY
    PORTONE_WEBHOOK_SECRET PAYMENT_PRICE_AMOUNT BANK_TRANSFER_ACCOUNT_INFO
  ].freeze

  setup do
    Commerce::CatalogBootstrap.call!
    @previous_payment_env = PAYMENT_ENV_KEYS.to_h { |key| [ key, ENV[key] ] }
    @product = Product.find_by!(code: "chatdox")
    @user = User.create!(name: "테스트 유저", email: "checkout-r2b@example.com", password: "password123", created_at: 30.days.ago)
  end

  teardown do
    @previous_payment_env.each { |key, value| restore_env(key, value) }
  end

  test "order submission with a missing product_code redirects to the bare checkout path, same as Chatdox's implicit default" do
    ENV["LEEDOX_COMMERCE_ENABLED"] = "false"
    sign_in

    assert_no_difference [ "Order.count", "PaymentTransaction.count" ] do
      post billing_orders_path, params: { order: { offer_code: "chatdox-1m-v1", requested_start_on: Date.current } }
    end
    assert_redirected_to billing_checkout_path
  end

  test "default configuration preserves the R2A inactive checkout and blocks direct order POST" do
    ENV["LEEDOX_COMMERCE_ENABLED"] = "false"
    @product.update!(sale_enabled: true)
    sign_in

    assert_no_difference [ "Order.count", "OrderItem.count", "PaymentTransaction.count" ] do
      get billing_checkout_path
    end
    assert_response :success
    assert_match(/준비하고 있습니다/, response.body)
    assert_select "script[src*='tosspayments']", count: 0
    assert_select "script[src*='portone']", count: 0

    assert_no_difference [ "Order.count", "PaymentTransaction.count" ] do
      post billing_orders_path, params: {
        order: { product_code: "chatdox", offer_code: "chatdox-1m-v1", requested_start_on: Date.current }
      }
    end
    assert_redirected_to billing_checkout_path
  end

  test "enabled checkout uses server offer despite a client amount parameter" do
    enable_chatdox_sales
    sign_in
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date

    get billing_checkout_path
    assert_response :success
    assert_select "input[name='order[offer_code]']", count: 4
    assert_select "input[name='order[requested_start_on]'][min=?][max=?]", today.iso8601, (today + 7.days).iso8601
    assert_select "input[type='submit'][value=?]", "주문하기"
    assert_match(/7,700원/, response.body)

    assert_difference [ "Order.count", "OrderItem.count", "PaymentTransaction.count" ], 1 do
      post billing_orders_path, params: {
        order: {
          product_code: "chatdox",
          offer_code: "chatdox-1m-v1",
          requested_start_on: today,
          total_amount: 1,
          duration_months: 99,
          currency: "USD"
        }
      }
    end

    order = Order.order(:created_at).last
    assert_redirected_to billing_order_path(order.public_id)
    assert_equal [ 1, 7_000, 700, 7_700, "KRW" ], [
      order.order_items.first.duration_months,
      order.supply_amount,
      order.vat_amount,
      order.total_amount,
      order.currency
    ]

    follow_redirect!
    assert_response :success
    assert_select "h1", text: "주문 내용을 확인해 주세요"
    assert_match(/7,700원/, response.body)
    assert_match(/자동 갱신되지 않는 일회성 선불 결제/, response.body)
  end

  test "enabled sale with missing PG configuration falls back to manual bank transfer checkout" do
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    @product.update!(sale_enabled: true)
    (PAYMENT_ENV_KEYS - %w[LEEDOX_COMMERCE_ENABLED]).each { |key| ENV.delete(key) }
    ENV["BANK_TRANSFER_ACCOUNT_INFO"] = "카카오뱅크 3333-01-1234567 (예금주 리독스)"
    sign_in
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date

    get billing_checkout_path
    assert_response :success
    assert_no_match(/준비하고 있습니다/, response.body)
    assert_select "input[name='order[offer_code]']", count: 4

    assert_difference [ "Order.count", "OrderItem.count", "PaymentTransaction.count" ], 1 do
      post billing_orders_path, params: {
        order: { product_code: "chatdox", offer_code: "chatdox-1m-v1", requested_start_on: today }
      }
    end

    order = Order.order(:created_at).last
    assert_equal "manual", order.provider
    assert_redirected_to billing_order_path(order.public_id)

    follow_redirect!
    assert_response :success
    assert_select "script[src*='portone']", count: 0
    assert_match(/카카오뱅크 3333-01-1234567/, response.body)
    assert_match(/24시간 이내 확인 후 라이선스가 발급됩니다/, response.body)
    assert_match(Regexp.new(Regexp.escape(order.public_id.delete("-").first(8).upcase)), response.body)
  end

  test "existing Chatdox period is displayed as a fixed extension date" do
    enable_chatdox_sales
    sign_in
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    last_on = today + 20.days
    License.create!(
      user: @user,
      product: @product,
      source: "paid",
      status: "active",
      starts_on: today,
      last_usable_on: last_on,
      access_ends_at: Commerce::PeriodCalculator::KST.local(*(last_on + 1.day).then { |date| [ date.year, date.month, date.day ] })
    )

    get billing_checkout_path

    assert_response :success
    assert_match(/결제하신 기간이 이어서 적용됩니다/, response.body)
    assert_select "input[type='hidden'][name='order[requested_start_on]'][value=?]", (last_on + 1.day).iso8601
    assert_select "input[type='date'][name='order[requested_start_on]']", count: 0
  end

  test "checkout blocks further stacking once the license chain already runs past 12 months out (handoff 0043)" do
    enable_chatdox_sales
    sign_in
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    last_on = today + 13.months
    License.create!(
      user: @user,
      product: @product,
      source: "coupon",
      status: "scheduled",
      starts_on: today,
      last_usable_on: last_on,
      access_ends_at: Commerce::PeriodCalculator::KST.local(*(last_on + 1.day).then { |date| [ date.year, date.month, date.day ] })
    )

    get billing_checkout_path
    assert_response :success
    assert_select "#license-stacking-capped-notice"
    assert_select "input[name='order[offer_code]']", count: 0
    assert_select "input[type='submit']", count: 0

    assert_no_difference [ "Order.count", "OrderItem.count", "PaymentTransaction.count" ] do
      post billing_orders_path, params: {
        order: { product_code: "chatdox", offer_code: "chatdox-1m-v1", requested_start_on: today }
      }
    end
    assert_redirected_to billing_checkout_path
  end

  test "Claudox has no purchase path even when global commerce is enabled" do
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    Product.find_by!(code: "claudox").update!(sale_enabled: false)
    sign_in

    assert_no_difference "Order.count" do
      post billing_orders_path, params: {
        order: { product_code: "claudox", offer_code: "chatdox-1m-v1", requested_start_on: Date.current }
      }
    end
    # Redirects back to Claudox's own checkout, not Chatdox's -- the whole
    # point of generalizing this gate was to stop it defaulting to whichever
    # product used to be the only one that existed.
    assert_redirected_to billing_checkout_path("claudox")
  end

  test "success callback resend finalizes one order and one license" do
    enable_chatdox_sales
    sign_in
    order = create_order
    payment = {
      "id" => order.public_id,
      "amount" => { "total" => order.total_amount },
      "currency" => order.currency,
      "status" => "PAID"
    }

    with_singleton_method(Portone::Client, :get_payment, ->(_payment_id) { payment }) do
      2.times do
        get billing_success_path, params: { paymentId: order.public_id }
        assert_redirected_to dashboard_path
      end
    end

    assert_equal "paid", order.reload.status
    assert_equal 1, order.licenses.count
    assert_equal 1, PaymentTransaction.where(purchase_order: order).count
    assert_equal({ "status" => "PAID" }, order.payment_transaction.reload.provider_payload)
  end

  test "success callback without matching order fails closed without legacy writes" do
    ENV["PAYMENT_PRICE_AMOUNT"] = "9900"
    sign_in

    assert_no_difference [ "Order.count", "PaymentTransaction.count", "License.count" ] do
      get billing_success_path, params: {
        orderId: "unmatched-order",
        paymentId: "unmatched-payment",
        paymentKey: "unmatched-key",
        amount: 9_900,
        currency: "KRW"
      }
    end

    assert_redirected_to billing_checkout_path
    assert_equal "주문을 확인할 수 없습니다. 상품 페이지에서 다시 시작해 주세요.", flash[:alert]
    assert_no_match(/unmatched-order|unmatched-payment|unmatched-key/, response.body)
  end

  test "success callback cannot finalize another users matching order" do
    enable_chatdox_sales
    other_user = User.create!(name: "테스트 유저", email: "other-checkout-user@example.com", password: "password123", created_at: 30.days.ago)
    other_order = Commerce::OrderCreator.call!(
      user: other_user,
      product_code: "chatdox",
      offer_code: "chatdox-1m-v1",
      requested_start_on: Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date,
      provider: "portone"
    )
    sign_in

    assert_no_difference [ "Order.count", "PaymentTransaction.count", "License.count" ] do
      get billing_success_path, params: { paymentId: other_order.public_id }
    end

    assert_redirected_to billing_cancel_path(product_code: "chatdox")
    assert_equal "pending", other_order.reload.status
    assert_empty other_order.licenses
  end

  test "PortOne webhook resend keeps one order transaction and license" do
    enable_chatdox_sales
    order = create_order
    payload = {
      "type" => "Transaction.Paid",
      "data" => { "paymentId" => order.public_id }
    }
    payment = {
      "id" => order.public_id,
      "amount" => { "total" => order.total_amount },
      "currency" => order.currency,
      "status" => "PAID",
      "paymentMethod" => { "card" => { "number" => "sensitive-card" } },
      "customer" => { "email" => "sensitive@example.com", "phoneNumber" => "010-0000-0000" },
      "token" => "sensitive-token",
      "receiptUrl" => "https://sensitive.example/receipt",
      "unknownFutureKey" => "sensitive-unknown"
    }

    verifier = ->(**_arguments) { true }
    payment_lookup = ->(_payment_id) { payment }
    with_singleton_method(Portone::WebhookVerifier, :verify!, verifier) do
      with_singleton_method(Portone::Client, :get_payment, payment_lookup) do
        assert_no_difference [ "Order.count", "PaymentTransaction.count" ] do
          assert_difference "License.count", 1 do
            2.times do
              post webhooks_portone_path,
                params: payload.to_json,
                headers: { "CONTENT_TYPE" => "application/json" }
              assert_response :success
            end
          end
        end
      end
    end

    assert_equal 1, Order.where(id: order.id).count
    assert_equal 1, PaymentTransaction.where(purchase_order: order).count
    assert_equal 1, order.reload.licenses.count
    assert_equal({ "status" => "PAID" }, order.payment_transaction.reload.provider_payload)
  end

  test "Dashboard is a learning hub (no order/license ledger) and My Page owns the full order summary" do
    enable_chatdox_sales
    sign_in
    order = create_order
    Commerce::OrderFinalizer.call!(order: order, payment: payment_for(order))

    get dashboard_path
    assert_response :success
    assert_match(/학습 진도/, response.body)
    assert_no_match(/상품별 라이선스/, response.body)
    assert_no_match(/결제 완료/, response.body)
    assert_select "a[href=?]", mypage_path, text: /마이페이지/

    get mypage_path
    assert_response :success
    assert_match(/상품별 라이선스/, response.body)
    assert_match(/Chatdox/, response.body)
    assert_match(/결제 완료/, response.body)
  end

  private

  def enable_chatdox_sales
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    ENV["PAYMENT_PROVIDER"] = "portone"
    ENV["PORTONE_API_SECRET"] = "test-api-secret"
    ENV["PORTONE_STORE_ID"] = "test-store-id"
    ENV["PORTONE_CHANNEL_KEY"] = "test-channel-key"
    ENV["PORTONE_WEBHOOK_SECRET"] = "test-portone-webhook-secret"
    @product.update!(sale_enabled: true)
  end

  def sign_in
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
  end

  def create_order(provider: "portone")
    Commerce::OrderCreator.call!(
      user: @user,
      product_code: "chatdox",
      offer_code: "chatdox-1m-v1",
      requested_start_on: Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date,
      provider: provider
    )
  end

  def payment_for(order)
    {
      provider: "portone",
      provider_payment_id: "dashboard-payment",
      order_id: order.public_id,
      amount: order.total_amount,
      currency: order.currency,
      provider_payload: {}
    }
  end

  def restore_env(key, value)
    value.nil? ? ENV.delete(key) : ENV[key] = value
  end

  def with_singleton_method(object, method_name, replacement)
    original = object.method(method_name)
    object.define_singleton_method(method_name, replacement)
    yield
  ensure
    object.define_singleton_method(method_name, original)
  end
end
