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

    # Responsive overflow container & whitespace-nowrap badges
    assert_select "div.overflow-x-auto"
    assert_select "th.whitespace-nowrap", text: /설정\/수정 ⚙️/
    assert_select "span.whitespace-nowrap", text: /판매 중|판매 중지/
    assert_select "span.whitespace-nowrap", text: /🎁 영구 무료 개방 \(유료 라이선스 없음\)/
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

  test "toggling is immediately reflected on the /claudox purchase gate and FAQ" do
    claudox = Product.find_by!(code: "claudox")
    claudox.update!(sale_enabled: false)

    get claudox_path
    assert_response :success
    assert_select "p", text: /현재는 구매 준비 중이며/
    assert_select "p", text: /아직 검토 중입니다/, count: 0
    assert_select "li", text: /템플릿 세트/, count: 0

    sign_in(@admin)
    patch admin_commerce_product_path(claudox)
    delete destroy_user_session_path

    get claudox_path
    assert_response :success
    assert_select "p", text: /구매 기간 동안 제공되는 Claudox 콘텐츠에 접근할 수 있습니다/
    assert_select "p", text: /아직 검토 중입니다/, count: 0
    assert_select "li", text: /템플릿 세트/, count: 0
  end

  test "admin can update pricing offers, discounts, and trial_chapter_limit dynamically" do
    sign_in(@admin)

    get edit_admin_commerce_product_path(@product)
    assert_response :success

    patch admin_commerce_product_path(@product), params: {
      product: {
        name: "Chatdox SaaS Engine",
        sale_enabled: "1",
        trial_chapter_limit: "4",
        offers_attributes: {
          "0" => { duration_months: "1", total_amount: "9900", discount_pct: "5", active: "1" },
          "1" => { duration_months: "3", total_amount: "28000", discount_pct: "10", active: "1" },
          "2" => { duration_months: "6", total_amount: "50000", discount_pct: "15", active: "1" },
          "3" => { duration_months: "12", total_amount: "88000", discount_pct: "25", active: "1" }
        }
      }
    }

    assert_redirected_to admin_commerce_products_path
    @product.reload
    assert_equal "Chatdox SaaS Engine", @product.name
    assert @product.sale_enabled?
    assert_equal 4, @product.trial_chapter_limit
    assert_equal 4, ProductContent.for("chatdox").trial_chapter_limit

    offer_12m = @product.product_offers.find_by!(duration_months: 12)
    assert_equal 88000, offer_12m.total_amount
    assert_equal 2500, offer_12m.discount_bps

    # Verify updated price renders on landing page
    get chatdox_path
    assert_response :success
    assert_match(/9,900원/, response.body)
    assert_match(/88,000원/, response.body)
    assert_match(/25% 할인/, response.body)
  end

  private

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
