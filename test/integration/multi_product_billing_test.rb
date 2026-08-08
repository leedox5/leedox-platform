require "test_helper"

class MultiProductBillingTest < ActionDispatch::IntegrationTest
  ENV_KEYS = %w[
    LEEDOX_COMMERCE_ENABLED PAYMENT_PROVIDER
    PORTONE_API_SECRET PORTONE_STORE_ID PORTONE_CHANNEL_KEY PORTONE_WEBHOOK_SECRET
    BANK_TRANSFER_ACCOUNT_INFO
  ].freeze

  setup do
    Commerce::CatalogBootstrap.call!
    @previous_env = ENV_KEYS.to_h { |key| [ key, ENV[key] ] }
    ENV_KEYS.each { |key| ENV.delete(key) }
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    @chatdox = Product.find_by!(code: "chatdox")
    @claudox = Product.find_by!(code: "claudox")
    @chatdox.update!(sale_enabled: true)
    @claudox.update!(sale_enabled: true)
    @user = User.create!(name: "테스트 유저", email: "multi-product@example.com", password: "password123", created_at: 30.days.ago)
    @admin = User.create!(name: "테스트 유저", email: "multi-product-admin@example.com", password: "password123", role: :admin)
  end

  teardown do
    @previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "Chatdox checkout is unaffected by generalization: bare URL, hidden field, real order" do
    configure_portone
    sign_in(@user)
    today = kst_today

    get billing_checkout_path
    assert_response :success
    assert_select "input[type=hidden][name='order[product_code]'][value=?]", "chatdox"
    assert_match(/7,700원/, response.body)

    assert_difference [ "Order.count", "OrderItem.count", "PaymentTransaction.count" ], 1 do
      post billing_orders_path, params: {
        order: { product_code: "chatdox", offer_code: "chatdox-1m-v1", requested_start_on: today }
      }
    end
    order = Order.order(:created_at).last
    assert_equal "chatdox", order.order_items.first.product_code
    assert_equal "portone", order.provider
    assert_redirected_to billing_order_path(order.public_id)

    follow_redirect!
    assert_response :success
    assert_select "script[src*='portone']"
  end

  test "Claudox checkout works end-to-end via the segmented URL with manual bank transfer" do
    # PortOne left unconfigured on purpose, so checkout_provider falls back to manual.
    sign_in(@user)
    today = kst_today

    get billing_checkout_path("claudox")
    assert_response :success
    assert_select "input[type=hidden][name='order[product_code]'][value=?]", "claudox"
    assert_match(/11,550원/, response.body)
    assert_no_match(/23,100원/, response.body) # that's Chatdox's 3-month price, not Claudox's

    assert_difference [ "Order.count", "OrderItem.count", "PaymentTransaction.count" ], 1 do
      post billing_orders_path, params: {
        order: { product_code: "claudox", offer_code: "claudox-3m-v1", requested_start_on: today }
      }
    end
    order = Order.order(:created_at).last
    assert_equal "claudox", order.order_items.first.product_code
    assert_equal "manual", order.provider
    assert_redirected_to billing_order_path(order.public_id)

    follow_redirect!
    assert_response :success
    assert_match(/무통장입금 안내/, response.body)

    delete destroy_user_session_path
    sign_in(@admin)
    assert_difference "License.count", 1 do
      post confirm_manual_payment_admin_commerce_order_path(order.public_id)
    end
    order.reload
    assert_equal "paid", order.status
    assert_equal "claudox", order.licenses.first.product.code
  end

  test "Claudox checkout works end-to-end with PortOne when it's configured" do
    configure_portone
    sign_in(@user)
    today = kst_today

    post billing_orders_path, params: {
      order: { product_code: "claudox", offer_code: "claudox-1m-v1", requested_start_on: today }
    }
    order = Order.order(:created_at).last
    assert_equal "claudox", order.order_items.first.product_code
    assert_equal "portone", order.provider

    payment = {
      "id" => order.public_id,
      "amount" => { "total" => order.total_amount },
      "currency" => order.currency,
      "status" => "PAID"
    }
    with_singleton_method(Portone::Client, :get_payment, ->(_payment_id) { payment }) do
      get billing_success_path, params: { paymentId: order.public_id }
    end

    assert_redirected_to dashboard_path
    order.reload
    assert_equal "paid", order.status
    assert_equal 1, order.licenses.count
    assert_equal "claudox", order.licenses.first.product.code
  end

  test "a Chatdox order and a Claudox order for the same user never mix up product, price, or license" do
    configure_portone
    chatdox_order = create_order(@user, product_code: "chatdox", offer_code: "chatdox-1m-v1")
    claudox_order = create_order(@user, product_code: "claudox", offer_code: "claudox-1m-v1")

    assert_equal "chatdox", chatdox_order.order_items.first.product_code
    assert_equal "claudox", claudox_order.order_items.first.product_code
    assert_equal 7_700, chatdox_order.total_amount
    assert_equal 3_850, claudox_order.total_amount
    assert_not_equal chatdox_order.order_items.first.product_id, claudox_order.order_items.first.product_id

    Commerce::OrderFinalizer.call!(order: chatdox_order, payment: payment_for(chatdox_order))

    chatdox_order.reload
    claudox_order.reload
    assert_equal "paid", chatdox_order.status
    assert_equal "pending", claudox_order.status, "finalizing the Chatdox order must not touch the Claudox order"
    assert_equal 1, chatdox_order.licenses.count
    assert_empty claudox_order.licenses
    assert_equal "chatdox", chatdox_order.licenses.first.product.code

    sign_in(@user)
    get mypage_path
    assert_response :success
    doc = Nokogiri::HTML(response.body)
    order_rows = doc.css("[aria-label='상품별 라이선스'] li").map(&:text)
    assert order_rows.any? { |text| text.include?("Chatdox") && text.include?("7,700") }
    assert order_rows.any? { |text| text.include?("Claudox") && text.include?("3,850") }
  end

  test "disabling one product's sales does not block or unblock the other product's checkout" do
    @claudox.update!(sale_enabled: false)
    sign_in(@user)
    today = kst_today

    # Chatdox still fully open.
    get billing_checkout_path
    assert_response :success
    assert_select "input[name='order[offer_code]']", count: 4

    # Claudox checkout page itself renders (no gate on GET checkout by product existence),
    # but shows the "not enabled" screen since Commerce::Sales.enabled_for? is false for it.
    get billing_checkout_path("claudox")
    assert_response :success
    assert_match(/준비하고 있습니다/, response.body)

    # And the order-creation gate rejects Claudox specifically, not Chatdox.
    assert_no_difference "Order.count" do
      post billing_orders_path, params: {
        order: { product_code: "claudox", offer_code: "claudox-1m-v1", requested_start_on: today }
      }
    end
    assert_redirected_to billing_checkout_path("claudox")

    assert_difference "Order.count", 1 do
      post billing_orders_path, params: {
        order: { product_code: "chatdox", offer_code: "chatdox-1m-v1", requested_start_on: today }
      }
    end
  end

  test "a brand-new third product needs no controller/route changes -- only a Product row, offers, and a partial call" do
    third = Product.create!(code: "widget_test", name: "Widget Test", active: true, sale_enabled: true)
    ProductOffer.create!(
      product: third, code: "widget_test-1m-v1", version: 1, duration_months: 1,
      supply_amount: 1_000, vat_amount: 100, total_amount: 1_100, discount_bps: 0, currency: "KRW", active: true
    )

    # B: a hypothetical new landing page would just call the shared partial
    # with the new product_code -- proven here without adding a throwaway
    # production route/view for a product that doesn't really exist yet.
    pricing_html = ApplicationController.render(
      partial: "shared/product_pricing", locals: { product_code: "widget_test" }
    )
    assert_match(/Widget Test 기간별 이용 안내/, pricing_html)
    assert_match(/1,100원/, pricing_html)
    assert_match(%r{href="/billing/checkout/widget_test"}, pricing_html)

    # A: and the actual checkout route/controllers -- zero code changes,
    # same generalized BillingController/BillingOrdersController as chatdox/claudox.
    sign_in(@user)
    get billing_checkout_path("widget_test")
    assert_response :success
    assert_select "input[type=hidden][name='order[product_code]'][value=?]", "widget_test"

    assert_difference [ "Order.count", "OrderItem.count", "PaymentTransaction.count" ], 1 do
      post billing_orders_path, params: {
        order: { product_code: "widget_test", offer_code: "widget_test-1m-v1", requested_start_on: kst_today }
      }
    end
    order = Order.order(:created_at).last
    assert_equal "widget_test", order.order_items.first.product_code
    assert_equal "manual", order.provider # PortOne unconfigured in this test
    assert_redirected_to billing_order_path(order.public_id)

    follow_redirect!
    assert_response :success
    assert_match(/무통장입금 안내/, response.body)
  end

  private

  def kst_today
    Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
  end

  def configure_portone
    ENV.update(
      "PAYMENT_PROVIDER" => "portone",
      "PORTONE_API_SECRET" => "test-api-secret",
      "PORTONE_STORE_ID" => "test-store-id",
      "PORTONE_CHANNEL_KEY" => "test-channel-key",
      "PORTONE_WEBHOOK_SECRET" => "test-portone-webhook-secret"
    )
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def create_order(user, product_code:, offer_code:)
    Commerce::OrderCreator.call!(
      user: user,
      product_code: product_code,
      offer_code: offer_code,
      requested_start_on: kst_today,
      provider: "portone"
    )
  end

  def payment_for(order)
    {
      provider: "portone",
      provider_payment_id: "multi-product-#{order.public_id}",
      order_id: order.public_id,
      amount: order.total_amount,
      currency: order.currency,
      provider_payload: {}
    }
  end

  def with_singleton_method(object, method_name, replacement)
    original = object.method(method_name)
    object.define_singleton_method(method_name, replacement)
    yield
  ensure
    object.define_singleton_method(method_name, original)
  end
end
