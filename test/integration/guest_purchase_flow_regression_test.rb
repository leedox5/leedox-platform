require "test_helper"

class GuestPurchaseFlowRegressionTest < ActionDispatch::IntegrationTest
  KST = Commerce::PeriodCalculator::KST

  setup do
    @old_env = ENV["LEEDOX_COMMERCE_ENABLED"]
    Commerce::CatalogBootstrap.call!
    @chatdox = Product.find_by!(code: "chatdox")
    @claudox = Product.find_by!(code: "claudox")
    @user = User.create!(name: "회귀 테스트 유저", email: "regression-user@example.com", password: "password123")
  end

  teardown do
    ENV["LEEDOX_COMMERCE_ENABLED"] = @old_env
  end

  test "1. Chatdox end-to-end guest purchase funnel" do
    enable_sales_for_all!

    # 1. Landing page
    get chatdox_path
    assert_response :success
    assert_select "a[href=?]", billing_checkout_path_for("chatdox"), text: "기간제 라이선스 구매"
    assert_match(/구매 절차: 로그인 또는 회원가입 → 이용 기간 확인 → 결제 → 대시보드에서 콘텐츠 이용/, response.body)

    # 2. Click purchase -> Auth redirect with purchase context
    get billing_checkout_path_for("chatdox")
    assert_redirected_to new_user_session_path
    follow_redirect!
    assert_select "div", text: /구매를 계속하려면 로그인이 필요합니다/

    # 3. Switch to sign up
    get new_user_registration_path(redirect_to: billing_checkout_path_for("chatdox"))
    assert_response :success
    assert_select "div", text: /구매를 계속하려면 회원가입이 필요합니다/

    # 4. Register new user -> Returns to Chatdox checkout
    assert_difference "User.count", 1 do
      post user_registration_path, params: {
        user: { name: "챗독스유저", email: "chatdox-e2e@example.com", password: "password123", password_confirmation: "password123" }
      }
    end
    assert_redirected_to billing_checkout_path_for("chatdox")
    follow_redirect!
    assert_response :success
    assert_select "p", text: "Chatdox"

    # 5. Submit order
    user = User.order(:created_at).last
    offer = @chatdox.product_offers.first!
    order = create_order_for(@chatdox, offer, user)

    # 6. Complete PortOne payment -> Redirects to dashboard with Chatdox notice and CTA
    with_fake_gateway(FakeSuccessGateway.new) do
      get billing_success_path, params: { paymentId: order.public_id }
    end
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_select "div", text: /Chatdox 결제가 완료되었습니다/
    assert_select "a[href=?]", product_chapter_path("chatdox", "01"), text: /첫 챕터 시작/

    # 7. Access Chatdox paid web content
    get product_chapter_path("chatdox", "06")
    assert_response :success
  end

  test "2. Claudox end-to-end guest purchase funnel" do
    enable_sales_for_all!

    # 1. Landing page
    get claudox_path
    assert_response :success
    assert_select "a[href=?]", billing_checkout_path_for("claudox"), text: "기간제 라이선스 구매"
    assert_match(/구매 절차: 로그인 또는 회원가입 → 이용 기간 확인 → 결제 → 대시보드에서 콘텐츠 이용/, response.body)

    # 2. Click purchase -> Auth redirect with purchase context
    get billing_checkout_path_for("claudox")
    assert_redirected_to new_user_session_path
    follow_redirect!
    assert_select "div", text: /구매를 계속하려면 로그인이 필요합니다/

    # 3. Switch to sign up
    get new_user_registration_path(redirect_to: billing_checkout_path_for("claudox"))
    assert_response :success
    assert_select "div", text: /구매를 계속하려면 회원가입이 필요합니다/

    # 4. Register new user -> Returns to Claudox checkout
    assert_difference "User.count", 1 do
      post user_registration_path, params: {
        user: { name: "클로드유저", email: "claudox-e2e@example.com", password: "password123", password_confirmation: "password123" }
      }
    end
    assert_redirected_to billing_checkout_path_for("claudox")
    follow_redirect!
    assert_response :success
    assert_select "p", text: "Claudox"

    # 5. Submit order
    user = User.order(:created_at).last
    offer = @claudox.product_offers.first!
    order = create_order_for(@claudox, offer, user)

    # 6. Complete PortOne payment -> Redirects to dashboard with Claudox notice and CTA
    with_fake_gateway(FakeSuccessGateway.new) do
      get billing_success_path, params: { paymentId: order.public_id }
    end
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_select "div", text: /Claudox 결제가 완료되었습니다/
    assert_select "a[href=?]", product_chapter_path("claudox", "01"), text: /첫 챕터 시작/

    # 7. Access Claudox paid web content
    get product_chapter_path("claudox", "06")
    assert_response :success
  end

  test "3. Preserving return destination across login <-> sign-up links and blocking external redirects" do
    enable_sales_for_all!

    # Chatdox preserved link check
    get billing_checkout_path_for("chatdox")
    assert_redirected_to new_user_session_path
    follow_redirect!
    assert_select "a[href*=?]", "redirect_to=%2Fbilling%2Fcheckout"

    # Claudox preserved link check
    reset!
    get billing_checkout_path_for("claudox")
    assert_redirected_to new_user_session_path
    follow_redirect!
    assert_select "a[href*=?]", "redirect_to=%2Fbilling%2Fcheckout%2Fclaudox"

    # External redirect attempt is ignored
    reset!
    get new_user_session_path(redirect_to: "https://evil.example.com/login")
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
    assert_redirected_to dashboard_path
  end

  test "4. Product and offer parameters match on checkout page" do
    enable_sales_for_all!
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }

    # Chatdox checkout
    get billing_checkout_path_for("chatdox")
    assert_response :success
    assert_select "input[name='order[product_code]'][value='chatdox']"
    @chatdox.product_offers.active.each do |offer|
      assert_select "input[name='order[offer_code]'][value=?]", offer.code
    end

    # Claudox checkout
    get billing_checkout_path_for("claudox")
    assert_response :success
    assert_select "input[name='order[product_code]'][value='claudox']"
    @claudox.product_offers.active.each do |offer|
      assert_select "input[name='order[offer_code]'][value=?]", offer.code
    end
  end

  test "5. Manual bank transfer pending order vs online payment status separation" do
    enable_sales_for_all!
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }

    # Manual bank transfer
    offer = @chatdox.product_offers.first!
    manual_order = Commerce::CheckoutSubmission.call!(
      user: @user,
      product_code: "chatdox",
      offer_code: offer.code,
      requested_start_on: Time.current.in_time_zone(KST).to_date,
      provider: Order::MANUAL_PROVIDER
    )
    get billing_order_path(manual_order.public_id)
    assert_response :success
    assert_select "span", text: /결제 대기 중/
    assert_no_match(/결제가 완료되었습니다/, response.body)

    # Online payment success
    online_order = create_order_for(@chatdox, offer)
    with_fake_gateway(FakeSuccessGateway.new) do
      get billing_success_path, params: { paymentId: online_order.public_id }
    end
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_select "div", text: /Chatdox 결제가 완료되었습니다/
  end

  test "6. Product-specific payment success CTA and cancellation/failure recovery routes" do
    enable_sales_for_all!
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }

    # Chatdox cancellation
    get billing_cancel_path(product_code: "chatdox")
    assert_redirected_to billing_checkout_path_for("chatdox")
    follow_redirect!
    assert_match(/결제가 취소되었습니다/, response.body)

    # Claudox cancellation
    get billing_cancel_path(product_code: "claudox")
    assert_redirected_to billing_checkout_path_for("claudox")
    follow_redirect!
    assert_match(/결제가 취소되었습니다/, response.body)

    # Chatdox failure
    chatdox_offer = @chatdox.product_offers.first!
    chatdox_order = create_order_for(@chatdox, chatdox_offer)
    with_fake_gateway(FakeFailureGateway.new) do
      get billing_success_path, params: { paymentId: chatdox_order.public_id }
    end
    assert_redirected_to billing_cancel_path(product_code: "chatdox")
    follow_redirect!
    assert_redirected_to billing_checkout_path_for("chatdox")
    follow_redirect!
    assert_match(/결제 승인에 실패했습니다/, response.body)

    # Claudox failure
    claudox_offer = @claudox.product_offers.first!
    claudox_order = create_order_for(@claudox, claudox_offer)
    with_fake_gateway(FakeFailureGateway.new) do
      get billing_success_path, params: { paymentId: claudox_order.public_id }
    end
    assert_redirected_to billing_cancel_path(product_code: "claudox")
    follow_redirect!
    assert_redirected_to billing_checkout_path_for("claudox")
    follow_redirect!
    assert_match(/결제 승인에 실패했습니다/, response.body)

    # Reconciliation failure
    with_fake_gateway(FakeReconciliationFailureGateway.new) do
      get billing_success_path, params: { paymentId: chatdox_order.public_id }
    end
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_match(/결제는 확인됐지만 라이선스 반영에 실패했습니다.*leedox@naver\.com/, response.body)
  end

  test "7. Global and product-level sale state combinations and product independence" do
    # Case 1: Chatdox enabled, Claudox disabled
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    @chatdox.update!(sale_enabled: true)
    @claudox.update!(sale_enabled: false)

    get chatdox_path
    assert_response :success
    assert_select "a[href=?]", billing_checkout_path_for("chatdox"), text: "기간제 라이선스 구매"
    assert_match(/구매 절차: 로그인 또는 회원가입/, response.body)

    get claudox_path
    assert_response :success
    assert_select "span", text: "구매 준비 중"
    assert_no_match(/구매 절차: 로그인 또는 회원가입/, response.body)

    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
    get billing_checkout_path_for("claudox")
    assert_response :success
    assert_select "h1", text: /준비하고 있습니다/

    # Case 2: Claudox enabled, Chatdox disabled
    delete destroy_user_session_path
    @chatdox.update!(sale_enabled: false)
    @claudox.update!(sale_enabled: true)

    get claudox_path
    assert_response :success
    assert_select "a[href=?]", billing_checkout_path_for("claudox"), text: "기간제 라이선스 구매"
    assert_match(/구매 절차: 로그인 또는 회원가입/, response.body)

    get chatdox_path
    assert_response :success
    assert_select "span", text: "구매 준비 중"
    assert_no_match(/구매 절차: 로그인 또는 회원가입/, response.body)
  end

  test "8. Non-regression of normal auth, Aistart free product, and unlicensed content block" do
    # Normal sign in and sign up without checkout context
    get new_user_session_path
    assert_response :success
    assert_no_match(/구매를 계속하려면 로그인이 필요합니다/, response.body)

    get new_user_registration_path
    assert_response :success
    assert_no_match(/구매를 계속하려면 회원가입이 필요합니다/, response.body)

    # Free product access (aistart) for unauthenticated guest
    get product_chapter_path("aistart", "01")
    assert_response :success

    # Paid chapter access blocked for unlicensed user -- redirected to that
    # product's own pricing section, not the generic home page (0045 R2-4).
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
    get product_chapter_path("chatdox", "06")
    assert_redirected_to "#{chatdox_path}#pricing"

    get product_chapter_path("claudox", "06")
    assert_redirected_to "#{claudox_path}#pricing"
  end

  private

  FakeSuccessGateway = Class.new do
    def verify_payment!(payment_id:, expected_amount:, expected_currency:)
      {
        "id" => payment_id,
        "amount" => { "total" => expected_amount },
        "currency" => expected_currency
      }
    end
  end

  FakeFailureGateway = Class.new do
    def verify_payment!(payment_id:, expected_amount:, expected_currency:)
      raise "Payment verification failed"
    end
  end

  FakeReconciliationFailureGateway = Class.new do
    def verify_payment!(payment_id:, expected_amount:, expected_currency:)
      raise ActiveRecord::ActiveRecordError, "DB persistence error"
    end
  end

  def with_fake_gateway(gateway_instance)
    original_method = Payments::Gateway.method(:for)
    Payments::Gateway.define_singleton_method(:for) { |_provider| gateway_instance }
    yield
  ensure
    Payments::Gateway.define_singleton_method(:for, original_method)
  end

  def billing_checkout_path_for(product_code)
    product_code.to_s == "chatdox" ? billing_checkout_path : billing_checkout_path(product_code)
  end

  def enable_sales_for_all!
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    @chatdox.update!(sale_enabled: true)
    @claudox.update!(sale_enabled: true)
  end

  def create_order_for(product, offer, user = @user)
    Commerce::OrderCreator.call!(
      user: user,
      product_code: product.code,
      offer_code: offer.code,
      requested_start_on: Time.current.in_time_zone(KST).to_date,
      provider: "portone"
    )
  end
end
