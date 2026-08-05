require "test_helper"

class GuestPurchaseFlowGuidanceTest < ActionDispatch::IntegrationTest
  KST = Commerce::PeriodCalculator::KST

  setup do
    @old_env = ENV["LEEDOX_COMMERCE_ENABLED"]
    Commerce::CatalogBootstrap.call!
    @chatdox = Product.find_by!(code: "chatdox")
    @claudox = Product.find_by!(code: "claudox")
    @user = User.create!(name: "게스트 테스트", email: "guest-funnel@example.com", password: "password123")
  end

  teardown do
    ENV["LEEDOX_COMMERCE_ENABLED"] = @old_env
  end

  test "1. Sign-in page displays purchase context banner when entering from Chatdox or Claudox checkout" do
    enable_sales!

    # Chatdox checkout funnel
    get billing_checkout_path("chatdox")
    assert_redirected_to new_user_session_path

    follow_redirect!
    assert_response :success
    assert_select "div", text: /구매를 계속하려면 로그인이 필요합니다/
    assert_select "div", text: /로그인 후 선택한 상품의 결제 화면으로 자동 이동합니다/

    delete destroy_user_session_path

    # Claudox checkout funnel
    get billing_checkout_path("claudox")
    assert_redirected_to new_user_session_path

    follow_redirect!
    assert_response :success
    assert_select "div", text: /구매를 계속하려면 로그인이 필요합니다/
    assert_select "div", text: /로그인 후 선택한 상품의 결제 화면으로 자동 이동합니다/
  end

  test "2. Normal sign-in and sign-up do not display purchase guidance banners" do
    get new_user_session_path
    assert_response :success
    assert_no_match(/구매를 계속하려면 로그인이 필요합니다/, response.body)

    get new_user_registration_path
    assert_response :success
    assert_no_match(/구매를 계속하려면 회원가입이 필요합니다/, response.body)
  end

  test "3. Sign-in preserves return destination and redirects to original product checkout" do
    enable_sales!

    # Chatdox return
    get billing_checkout_path("chatdox")
    assert_redirected_to new_user_session_path

    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
    assert_redirected_to billing_checkout_path("chatdox")

    delete destroy_user_session_path

    # Claudox return
    get billing_checkout_path("claudox")
    assert_redirected_to new_user_session_path

    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
    assert_redirected_to billing_checkout_path("claudox")
  end

  test "4. Sign-up preserves return destination and redirects to original product checkout" do
    enable_sales!

    # Chatdox registration return
    get billing_checkout_path("chatdox")
    assert_redirected_to new_user_session_path

    get new_user_registration_path(redirect_to: billing_checkout_path("chatdox"))
    assert_response :success
    assert_select "div", text: /구매를 계속하려면 회원가입이 필요합니다/

    assert_difference "User.count", 1 do
      post user_registration_path, params: {
        user: { name: "신규회원", email: "new-purchaser@example.com", password: "password123", password_confirmation: "password123" }
      }
    end
    assert_redirected_to billing_checkout_path("chatdox")
  end

  test "4-b. Claudox sign-up preserves return destination and redirects to Claudox checkout" do
    enable_sales!

    get billing_checkout_path("claudox")
    assert_redirected_to new_user_session_path

    get new_user_registration_path(redirect_to: billing_checkout_path("claudox"))
    assert_response :success
    assert_select "div", text: /구매를 계속하려면 회원가입이 필요합니다/

    assert_difference "User.count", 1 do
      post user_registration_path, params: {
        user: { name: "클로드회원", email: "claudox-purchaser@example.com", password: "password123", password_confirmation: "password123" }
      }
    end
    assert_redirected_to billing_checkout_path("claudox")
  end

  test "5. External URL parameters are blocked from being stored as redirect destinations" do
    get new_user_session_path(redirect_to: "https://attacker.com/malicious")
    assert_response :success

    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
    assert_redirected_to dashboard_path
  end

  test "6. Product page displays purchase process guidance when sales enabled, omits it when sales disabled" do
    # When sales enabled
    enable_sales!
    get chatdox_path
    assert_response :success
    assert_match(/구매 절차: 로그인 또는 회원가입 → 이용 기간 확인 → 결제 → 대시보드에서 콘텐츠 이용/, response.body)

    # When sales disabled
    disable_sales!
    get chatdox_path
    assert_response :success
    assert_select "span", text: "구매 준비 중"
    assert_no_match(/구매 절차: 로그인 또는 회원가입/, response.body)
  end

  test "7. PortOne payment success identifies purchased product and redirects to dashboard with clear notice" do
    enable_sales!
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }

    offer = @chatdox.product_offers.first!
    order = create_order_for(@chatdox, offer)

    with_fake_gateway(FakeSuccessGateway.new) do
      get billing_success_path, params: { paymentId: order.public_id }
    end

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_select "div", text: /Chatdox 결제가 완료되었습니다/
    assert_select "a[href=?]", product_chapter_path("chatdox", "01"), text: /첫 챕터 시작/
  end

  test "7-b. PortOne payment success for Claudox identifies Claudox product and redirects to dashboard with Claudox content CTA" do
    enable_sales!
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }

    offer = @claudox.product_offers.first!
    order = create_order_for(@claudox, offer)

    with_fake_gateway(FakeSuccessGateway.new) do
      get billing_success_path, params: { paymentId: order.public_id }
    end

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_select "div", text: /Claudox 결제가 완료되었습니다/
    assert_select "a[href=?]", product_chapter_path("claudox", "01"), text: /첫 챕터 시작/
  end

  test "8. Manual bank transfer pending order stays on order page with deposit instructions and does not show payment success" do
    enable_sales!
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }

    offer = @chatdox.product_offers.first!
    order = Commerce::CheckoutSubmission.call!(
      user: @user,
      product_code: "chatdox",
      offer_code: offer.code,
      requested_start_on: Time.current.in_time_zone(KST).to_date,
      provider: Order::MANUAL_PROVIDER
    )

    get billing_order_path(order.public_id)
    assert_response :success
    assert_match(/아래 계좌로 입금해 주세요/, response.body)
    assert_no_match(/결제가 완료되었습니다/, response.body)
  end

  test "9. Cancel, approval failure, and reconciliation failure provide distinct next action guidance" do
    enable_sales!
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }

    # Cancellation with product context
    get billing_cancel_path(product_code: "chatdox")
    assert_redirected_to billing_checkout_path_for("chatdox")
    follow_redirect!
    assert_match(/결제가 취소되었습니다/, response.body)

    # Failure with product context
    offer = @chatdox.product_offers.first!
    order = create_order_for(@chatdox, offer)

    with_fake_gateway(FakeFailureGateway.new) do
      get billing_success_path, params: { paymentId: order.public_id }
    end
    assert_redirected_to billing_cancel_path(product_code: "chatdox")
    follow_redirect!
    assert_redirected_to billing_checkout_path_for("chatdox")
    follow_redirect!
    assert_match(/결제 승인에 실패했습니다/, response.body)

    # Reconciliation failure
    with_fake_gateway(FakeReconciliationFailureGateway.new) do
      get billing_success_path, params: { paymentId: order.public_id }
    end
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_match(/결제는 확인됐지만 라이선스 반영에 실패했습니다.*leedox@naver\.com/, response.body)
  end

  test "9-b. Claudox cancel and approval failure redirect to Claudox checkout with product context" do
    enable_sales!
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }

    # Cancellation for Claudox
    get billing_cancel_path(product_code: "claudox")
    assert_redirected_to billing_checkout_path_for("claudox")
    follow_redirect!
    assert_match(/결제가 취소되었습니다/, response.body)

    # Approval failure for Claudox
    offer = @claudox.product_offers.first!
    order = create_order_for(@claudox, offer)

    with_fake_gateway(FakeFailureGateway.new) do
      get billing_success_path, params: { paymentId: order.public_id }
    end
    assert_redirected_to billing_cancel_path(product_code: "claudox")
    follow_redirect!
    assert_redirected_to billing_checkout_path_for("claudox")
    follow_redirect!
    assert_match(/결제 승인에 실패했습니다/, response.body)
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

  def enable_sales!
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    @chatdox.update!(sale_enabled: true)
    @claudox.update!(sale_enabled: true)
  end

  def disable_sales!
    ENV["LEEDOX_COMMERCE_ENABLED"] = "false"
    @chatdox.update!(sale_enabled: false)
    @claudox.update!(sale_enabled: false)
  end

  def create_order_for(product, offer)
    Commerce::OrderCreator.call!(
      user: @user,
      product_code: product.code,
      offer_code: offer.code,
      requested_start_on: Time.current.in_time_zone(KST).to_date,
      provider: "portone"
    )
  end
end
