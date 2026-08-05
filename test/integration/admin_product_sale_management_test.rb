require "test_helper"

class AdminProductSaleManagementTest < ActionDispatch::IntegrationTest
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
    @product = Product.find_by!(code: "chatdox")
    @product.update!(sale_enabled: false)
    @admin = User.create!(name: "테스트 유저", email: "product-admin@example.com", password: "password123", role: :admin)
    @other = User.create!(name: "테스트 유저", email: "product-other@example.com", password: "password123")
  end

  teardown do
    @previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "index and toggle require admin authentication" do
    get admin_commerce_products_path
    assert_redirected_to new_user_session_path
    patch admin_commerce_product_path(@product)
    assert_redirected_to new_user_session_path

    sign_in(@other)
    get admin_commerce_products_path
    assert_redirected_to root_path
    patch admin_commerce_product_path(@product)
    assert_redirected_to root_path
    assert_not @product.reload.sale_enabled?

    delete destroy_user_session_path
    sign_in(@admin)
    get admin_commerce_products_path
    assert_response :success
  end

  test "toggling flips sale_enabled and records a commerce audit event" do
    sign_in(@admin)

    assert_difference "CommerceAuditEvent.count", 1 do
      patch admin_commerce_product_path(@product)
    end
    assert_redirected_to admin_commerce_products_path
    assert @product.reload.sale_enabled?

    event = CommerceAuditEvent.order(:created_at).last
    assert_equal "product_sale_toggled", event.action
    assert_equal @admin, event.actor
    assert_equal @product, event.auditable
    assert_equal "disabled", event.from_state
    assert_equal "enabled", event.to_state

    assert_difference "CommerceAuditEvent.count", 1 do
      patch admin_commerce_product_path(@product)
    end
    assert_not @product.reload.sale_enabled?
  end

  test "toggling is immediately reflected on the /chatdox purchase gate and FAQ" do
    get chatdox_path
    assert_response :success
    assert_select "a[href=?]", billing_checkout_path, count: 0
    assert_select "p", text: /현재는 구매 준비 중이며/
    assert_select "p", text: /판매 재개 후/, count: 0
    assert_select "p", text: /Chatdox Lab/, count: 0

    sign_in(@admin)
    patch admin_commerce_product_path(@product)
    delete destroy_user_session_path

    get chatdox_path
    assert_response :success
    assert_select "a[href=?]", billing_checkout_path, text: /기간제 라이선스 구매/
    assert_select "p", text: /구매한 라이선스 기간 동안 Chatdox의 유료 문서에 접근할 수 있습니다/
    assert_select "p", text: /판매 재개 후/, count: 0
    assert_select "p", text: /Chatdox Lab/, count: 0
  end

  private

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
