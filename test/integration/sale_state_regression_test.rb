require "test_helper"

class SaleStateRegressionTest < ActionDispatch::IntegrationTest
  include ActionView::Helpers::NumberHelper
  setup do
    Commerce::CatalogBootstrap.call!
    @previous_env = %w[LEEDOX_COMMERCE_ENABLED PAYMENT_PROVIDER PORTONE_API_SECRET PORTONE_STORE_ID PORTONE_CHANNEL_KEY PORTONE_WEBHOOK_SECRET].to_h { |key| [ key, ENV[key] ] }
    ENV.update(
      "LEEDOX_COMMERCE_ENABLED" => "true",
      "PAYMENT_PROVIDER" => "portone",
      "PORTONE_API_SECRET" => "test-api",
      "PORTONE_STORE_ID" => "test-store",
      "PORTONE_CHANNEL_KEY" => "test-channel",
      "PORTONE_WEBHOOK_SECRET" => "test-webhook"
    )

    @user = User.create!(name: "테스트 사용자", email: "regression-user@example.com", password: "password123")
    @chatdox = Product.find_by!(code: "chatdox")
    @claudox = Product.find_by!(code: "claudox")
    @aistart = Product.find_by!(code: "aistart")
  end

  teardown do
    @previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "/pricing renders badges, prices, and CTAs consistently for Chatdox and Claudox under enabled/disabled sales states" do
    # When Chatdox and Claudox have sale_enabled: true
    @chatdox.update!(sale_enabled: true)
    @claudox.update!(sale_enabled: true)

    # 1. Logged out user view on /pricing
    get pricing_path
    assert_response :success

    # Badges
    assert_select "span.rounded-full", text: "판매 중", count: 2
    assert_select "span.rounded-full", text: "무료 이용 가능", count: 1

    # Prices
    chatdox_cheapest = @chatdox.product_offers.active.ordered.first
    claudox_cheapest = @claudox.product_offers.active.ordered.first
    assert_select "p", text: /최저 #{number_with_delimiter(chatdox_cheapest.total_amount)}원부터/
    assert_select "p", text: /최저 #{number_with_delimiter(claudox_cheapest.total_amount)}원부터/

    # Detail CTA links for logged out user (redirect_to)
    assert_select "a[href=?]", new_user_session_path(redirect_to: chatdox_path), text: "자세히 보기"
    assert_select "a[href=?]", new_user_session_path(redirect_to: claudox_path), text: "자세히 보기"

    # 2. Logged in user view on /pricing
    sign_in(@user)
    get pricing_path
    assert_response :success

    assert_select "a[href=?]", chatdox_path, text: "자세히 보기"
    assert_select "a[href=?]", claudox_path, text: "자세히 보기"
    delete destroy_user_session_path

    # 3. When sale_enabled is false for Chatdox & Claudox
    @chatdox.update!(sale_enabled: false)
    @claudox.update!(sale_enabled: false)

    get pricing_path
    assert_response :success
    assert_select "span.rounded-full", text: "준비 중", minimum: 2
    assert_select "span.rounded-full", text: "무료 이용 가능", count: 1
    # Prices remain displayed from bootstrap catalog even when sales are paused
    assert_select "p", text: /최저 #{number_with_delimiter(chatdox_cheapest.total_amount)}원부터/
    assert_select "p", text: /최저 #{number_with_delimiter(claudox_cheapest.total_amount)}원부터/
  end

  test "Logged-out user sign in and seamless return to original checkout destination" do
    @chatdox.update!(sale_enabled: true)
    @claudox.update!(sale_enabled: true)

    # 1. Chatdox checkout redirect flow
    get billing_checkout_path
    assert_redirected_to new_user_session_path

    # Sign in and verify redirect to original stored checkout location
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
    assert_redirected_to billing_checkout_path
    follow_redirect!
    assert_response :success
    assert_select "h1", text: /기간제 라이선스 선택/
    assert_select "input[type=submit]", value: "주문하기"

    delete destroy_user_session_path

    # 2. Claudox checkout redirect flow
    get billing_checkout_path("claudox")
    assert_redirected_to new_user_session_path

    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
    assert_redirected_to billing_checkout_path("claudox")
    follow_redirect!
    assert_response :success
    assert_select "h1", text: /기간제 라이선스 선택/
    assert_select "input[type=submit]", value: "주문하기"
  end

  test "Chatdox sales state consistency across /pricing, /chatdox, and checkout gate" do
    # 1. Disabled sales state
    @chatdox.update!(sale_enabled: false)

    # /chatdox page displays disabled state copy and button
    get chatdox_path
    assert_response :success
    assert_select "span", text: "구매 준비 중"
    assert_select "p", text: /현재는 구매 준비 중이며/
    assert_select "p", text: /판매 재개 후/, count: 0
    assert_select "p", text: /Chatdox Lab/, count: 0

    # Visiting checkout directly when disabled shows disabled screen even for signed-in user
    sign_in(@user)
    get billing_checkout_path
    assert_response :success
    assert_select "h1", text: /신규 결제를 준비하고 있습니다/
    delete destroy_user_session_path

    # 2. Enabled sales state
    @chatdox.update!(sale_enabled: true)

    # Logged-out user sees active purchase CTA
    get chatdox_path
    assert_response :success
    assert_select "a[href=?]", billing_checkout_path, text: /기간제 라이선스 구매/
    assert_select "p", text: /구매한 라이선스 기간 동안 Chatdox의 유료 문서에 접근할 수 있습니다/

    # Logged-in user checkout attempt opens enabled checkout screen with active offers
    sign_in(@user)
    get billing_checkout_path
    assert_response :success
    assert_select "form"
    assert_select "input[type=submit]", value: "주문하기"
  end

  test "Claudox sales state consistency across /pricing, /claudox, and checkout gate" do
    # 1. Disabled sales state
    @claudox.update!(sale_enabled: false)

    # /claudox page displays disabled state copy and button
    get claudox_path
    assert_response :success
    assert_select "span", text: "구매 준비 중"
    assert_select "p", text: /현재는 구매 준비 중이며/
    assert_select "p", text: /아직 검토 중입니다/, count: 0
    assert_select "li", text: /템플릿 세트/, count: 0

    # Visiting checkout directly when disabled shows disabled screen even for signed-in user
    sign_in(@user)
    get billing_checkout_path("claudox")
    assert_response :success
    assert_select "h1", text: /신규 결제를 준비하고 있습니다/
    delete destroy_user_session_path

    # 2. Enabled sales state
    @claudox.update!(sale_enabled: true)

    # Logged-out user sees active purchase CTA
    get claudox_path
    assert_response :success
    assert_select "a[href=?]", billing_checkout_path("claudox"), text: /기간제 라이선스 구매/
    assert_select "p", text: /구매 기간 동안 제공되는 Claudox 콘텐츠에 접근할 수 있습니다/

    # Logged-in user checkout attempt opens enabled checkout screen with active offers
    sign_in(@user)
    get billing_checkout_path("claudox")
    assert_response :success
    assert_select "form"
    assert_select "input[type=submit]", value: "주문하기"
  end

  test "Global LEEDOX_COMMERCE_ENABLED=false overrides product-level sale_enabled" do
    @chatdox.update!(sale_enabled: true)
    @claudox.update!(sale_enabled: true)

    ENV["LEEDOX_COMMERCE_ENABLED"] = "false"

    get pricing_path
    assert_response :success
    assert_select "span.rounded-full", text: "준비 중", minimum: 2

    get chatdox_path
    assert_response :success
    assert_select "span", text: "구매 준비 중"
    assert_select "p", text: /현재는 구매 준비 중이며/

    get claudox_path
    assert_response :success
    assert_select "span", text: "구매 준비 중"
    assert_select "p", text: /현재는 구매 준비 중이며/
  end

  private

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
