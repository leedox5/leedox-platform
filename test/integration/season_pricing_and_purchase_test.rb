require "test_helper"

# Handoff 0057 -- admin pricing panel, customer purchase flow, license-gated
# Season content, and isolation from the four term products' catalog.
class SeasonPricingAndPurchaseTest < ActionDispatch::IntegrationTest
  KST = Commerce::PeriodCalculator::KST
  ENV_KEYS = %w[LEEDOX_COMMERCE_ENABLED PAYMENT_PROVIDER PORTONE_API_SECRET PORTONE_STORE_ID PORTONE_CHANNEL_KEY
                PORTONE_KAKAOPAY_CHANNEL_KEY PORTONE_WEBHOOK_SECRET BANK_TRANSFER_ACCOUNT_INFO].freeze

  setup do
    Commerce::CatalogBootstrap.call!
    @previous_env = ENV_KEYS.to_h { |key| [ key, ENV[key] ] }
    ENV_KEYS.each { |key| ENV.delete(key) }
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    ENV["BANK_TRANSFER_ACCOUNT_INFO"] = "테스트은행 000-00-0000"

    @admin = User.create!(name: "관리자", email: "sp-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @buyer = User.create!(name: "구매자", email: "sp-buyer-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    @other = User.create!(name: "다른사람", email: "sp-other-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)

    @line = ProductLine.create!(internal_name: "A", customer_name: "제품 A", slug: "product-a", introduction: "소개", status: "published")
    @s1 = @line.product_seasons.create!(internal_name: "S01", customer_title: "첫 판", season_code: "S01", slug: "s01", status: "published", visibility: "public")
    @s2 = @line.product_seasons.create!(internal_name: "S02", customer_title: "둘째 판", season_code: "S02", slug: "s02", status: "published", visibility: "public")
    @ep1 = @s1.content_episodes.create!(position: 1, customer_title: "S01 첫 편", body: "# S01\n\nS01 유료 본문", status: "published")
    @ep2 = @s2.content_episodes.create!(position: 1, customer_title: "S02 첫 편", body: "# S02\n\nS02 유료 본문", status: "published")
    @asset = @ep1.content_assets.create!(title: "S01 소스", kind: "소스코드", position: 1,
      file: { io: file_fixture("assets/sample.zip").open, filename: "sample.zip", content_type: "application/zip" })
  end

  teardown do
    @previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def sign_out
    delete destroy_user_session_path
  end

  def open_sale!(season, amount = 33_000)
    Commerce::SeasonSales.set_price!(season: season, total_amount: amount, actor: @admin)
    Commerce::SeasonSales.start_sale!(season: season, actor: @admin)
    season.reload
  end

  def buy!(user, season)
    order = Commerce::OrderCreator.call!(user: user, product_code: season.reload.product.code, offer_code: season.lifetime_offer.code, requested_start_on: nil, provider: "manual")
    Commerce::ConfirmManualPayment.call!(order: order, actor: @admin)
    order.reload
  end

  # --- admin panel ---------------------------------------------------------

  test "only admins can use the sale panel and its actions" do
    sign_in(@buyer)
    get edit_admin_product_season_path(@s1)
    assert_redirected_to root_path
    assert_no_difference [ "Product.count", "ProductOffer.count" ] do
      patch admin_product_season_sale_path(@s1), params: { sale: { total_amount: 1000 } }
      patch start_admin_product_season_sale_path(@s1)
      patch stop_admin_product_season_sale_path(@s1)
    end
    sign_out
    patch admin_product_season_sale_path(@s1), params: { sale: { total_amount: 1000 } }
    assert_redirected_to new_user_session_path
  end

  test "the Season edit screen shows a stopped-by-default sale panel with the warnings" do
    sign_in(@admin)
    get edit_admin_product_season_path(@s1)
    assert_response :success
    assert_select "#sale-settings"
    assert_includes css_select("#sale-settings").text, "판매 설정 없음 (무료 공개)"
    assert_select "#sale-settings input[name='sale[total_amount]']"
    assert_select "#sale-settings form[action=?]", admin_product_season_sale_path(@s1)
    assert_select "#sale-settings input[type=submit][data-turbo-confirm*='구매자만 이용']", 1
    assert_select "#sale-settings button", text: /판매 시작/, count: 0
    assert_includes css_select("#sale-settings").text, "신규 구매만"
    assert_includes css_select("#sale-settings").text, "S02는 열리지 않습니다"
  end

  test "admin flow: save price -> product created stopped -> start (with confirm) -> stop (existing owners kept)" do
    sign_in(@admin)
    assert_difference [ "Product.count", "ProductOffer.count" ], 1 do
      patch admin_product_season_sale_path(@s1), params: { sale: { total_amount: "33,000" } }
    end
    assert_redirected_to edit_admin_product_season_path(@s1)
    assert_match(/판매는 아직 중지 상태/, flash[:notice])
    product = @s1.reload.product
    assert_not product.sale_enabled?

    get edit_admin_product_season_path(@s1)
    assert_includes css_select("#sale-settings").text, "판매 중지"
    assert_includes css_select("#sale-settings").text, "33,000원"
    assert_includes css_select("#sale-settings").text, product.code
    confirm = css_select("#sale-settings form[action='#{start_admin_product_season_sale_path(@s1)}'] button").first["data-turbo-confirm"]
    assert_includes confirm, "33,000원"

    patch start_admin_product_season_sale_path(@s1)
    assert product.reload.sale_enabled?
    get edit_admin_product_season_path(@s1)
    assert_includes css_select("#sale-settings").text, "판매 중"
    stop_confirm = css_select("#sale-settings form[action='#{stop_admin_product_season_sale_path(@s1)}'] button").first["data-turbo-confirm"]
    assert_includes stop_confirm, "기존 구매자"

    buy!(@buyer, @s1)
    patch stop_admin_product_season_sale_path(@s1)
    assert_match(/기존 구매자의 이용은 유지/, flash[:notice])
    assert_not product.reload.sale_enabled?
    assert Entitlements::ProductAccess.allowed?(user: @buyer, product_code: product.code)
  end

  test "bad input is rejected with a message and changes nothing" do
    sign_in(@admin)
    assert_no_difference [ "Product.count", "ProductOffer.count" ] do
      patch admin_product_season_sale_path(@s1), params: { sale: { total_amount: "-1" } }
      assert_redirected_to edit_admin_product_season_path(@s1)
      assert_match(/0원 이상/, flash[:alert])
    end
    patch start_admin_product_season_sale_path(@s1)
    assert_match(/가격을 먼저/, flash[:alert])
    assert_nil @s1.reload.product
  end

  # --- 0-won (free) Seasons ---------------------------------------------------

  test "admin can save 0 as the price; the panel then speaks of a free Season and opens free start" do
    sign_in(@admin)
    patch admin_product_season_sale_path(@s1), params: { sale: { total_amount: "0" } }
    assert_redirected_to edit_admin_product_season_path(@s1)
    assert_match(/판매 설정을 만들었습니다/, flash[:notice])
    assert @s1.reload.free?

    get edit_admin_product_season_path(@s1)
    panel = css_select("#sale-settings").text
    assert_includes panel, "무료 · 시작 중지"
    assert_includes panel, "무료 (0원)"
    assert_select "#sale-settings input[name='sale[total_amount]'][min='0']"
    confirm = css_select("#sale-settings form[action='#{start_admin_product_season_sale_path(@s1)}'] button").first["data-turbo-confirm"]
    assert_includes confirm, "결제 없이"

    patch start_admin_product_season_sale_path(@s1)
    get edit_admin_product_season_path(@s1)
    assert_includes css_select("#sale-settings").text, "무료 이용 시작 가능"
    assert_select "#sale-settings form[action=?]", stop_admin_product_season_sale_path(@s1)
  end

  test "saving 0 on an on-sale Season stops the sale and tells the admin" do
    open_sale!(@s1, 33_000)
    sign_in(@admin)
    patch admin_product_season_sale_path(@s1), params: { sale: { total_amount: "0" } }
    assert_match(/안전을 위해 판매를 중지/, flash[:notice])
    assert_not @s1.reload.product.sale_enabled?
    get edit_admin_product_season_path(@s1)
    assert_includes css_select("#sale-settings").text, "무료 · 시작 중지"
    assert_includes css_select("#sale-settings").text, "자동으로 중지됩니다"
  end

  test "free Season page: 무료 shown, start button for signed-in users, login link for guests, 'not available' while stopped" do
    Commerce::SeasonSales.set_price!(season: @s1, total_amount: 0, actor: @admin)
    get product_season_path(@line.slug, @s1.slug)
    assert_includes css_select("#season-purchase").text, "현재 시작할 수 없습니다"
    assert_select "#season-purchase form", 0
    assert_no_match(/구매하기|원/, css_select("#season-purchase").text)

    Commerce::SeasonSales.start_sale!(season: @s1, actor: @admin)
    code = @s1.reload.product.code
    get product_season_path(@line.slug, @s1.slug)
    assert_includes css_select("#season-purchase").text, "무료 · 무기한 이용"
    assert_no_match(/구매하기|VAT|₩/, css_select("#season-purchase").text)
    assert_select "#season-purchase a[href=?]", billing_checkout_path(code), text: "로그인하고 무료로 시작"

    sign_in(@buyer)
    get product_season_path(@line.slug, @s1.slug)
    assert_select "#season-purchase form[action=?] button", claim_free_season_path(code), text: "무료로 이용 시작"
  end

  test "free start: locked before, POST creates one indefinite license without any order, open after, and a repeat press is harmless" do
    open_sale!(@s1, 0)
    code = @s1.product.code
    episode = product_season_episode_path(@line.slug, @s1.slug, "01")
    download = product_season_episode_asset_path(@line.slug, @s1.slug, "01", @asset.id)

    post claim_free_season_path(code)
    assert_redirected_to new_user_session_path

    sign_in(@buyer)
    get episode
    assert_redirected_to product_season_path(@line.slug, @s1.slug)
    get download
    assert_redirected_to product_season_path(@line.slug, @s1.slug)

    assert_no_difference [ "Order.count", "OrderItem.count", "PaymentTransaction.count" ] do
      assert_difference "License.count", 1 do
        post claim_free_season_path(code)
      end
    end
    assert_redirected_to product_season_path(@line.slug, @s1.slug)
    assert_match(/무료 이용을 시작했습니다/, flash[:notice])
    license = @buyer.licenses.sole
    assert_equal [ "free", true ], [ license.source, license.indefinite? ]

    get episode
    assert_response :success
    assert_match(/S01 유료 본문/, response.body)
    get download
    assert_response :success
    get product_season_path(@line.slug, @s1.slug)
    assert_includes css_select("#season-purchase").text, "무료로 이용 중인 Season입니다 · 무기한 이용"
    assert_select "#season-purchase form", 0

    assert_no_difference "License.count" do
      post claim_free_season_path(code)
    end
    assert_match(/이미 이용 중/, flash[:notice])
    get mypage_path
    assert_response :success
    assert_includes response.body, "무기한"
  end

  test "a second user, and the other Season, are unaffected by someone's free start" do
    open_sale!(@s1, 0)
    open_sale!(@s2, 55_000)
    sign_in(@buyer)
    post claim_free_season_path(@s1.product.code)
    sign_out

    sign_in(@other)
    get product_season_episode_path(@line.slug, @s1.slug, "01")
    assert_redirected_to product_season_path(@line.slug, @s1.slug)
    sign_out
    sign_in(@buyer)
    get product_season_episode_path(@line.slug, @s2.slug, "01")
    assert_redirected_to product_season_path(@line.slug, @s2.slug)
  end

  test "free checkout page shows the free start (no order form), works with payments off, and orders can't be forced through" do
    open_sale!(@s1, 0)
    ENV["LEEDOX_COMMERCE_ENABLED"] = "false"
    code = @s1.product.code

    get billing_checkout_path(code)
    assert_redirected_to new_user_session_path

    sign_in(@buyer)
    get billing_checkout_path(code)
    assert_response :success
    assert_select "#season-free-start form[action=?]", claim_free_season_path(code)
    assert_select "form[action=?]", billing_orders_path, 0
    assert_no_match(/VAT|공급가|결제 수단/, css_select("main").text)

    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    assert_no_difference [ "Order.count", "PaymentTransaction.count" ] do
      post billing_orders_path, params: { order: { product_code: code, offer_code: @s1.lifetime_offer.code, payment_method: "manual" } }
    end
    assert_redirected_to billing_checkout_path(code)
  end

  test "free start is refused after the admin stops it, for priced Seasons, and for non-Season products" do
    open_sale!(@s1, 0)
    Commerce::SeasonSales.stop_sale!(season: @s1, actor: @admin)
    sign_in(@buyer)
    assert_no_difference "License.count" do
      post claim_free_season_path(@s1.product.code)
      assert_redirected_to product_season_path(@line.slug, @s1.slug)
      assert_match(/무료로 시작할 수 없습니다/, flash[:alert])

      open_sale!(@s2, 33_000)
      post claim_free_season_path(@s2.product.code)
      assert_match(/무료로 시작할 수 없습니다/, flash[:alert])

      post claim_free_season_path("chatdox")
      assert_redirected_to root_path
    end
    post claim_free_season_path("no_such_product")
    assert_response :not_found
  end

  test "the paid Season purchase flow is unchanged next to a free one" do
    open_sale!(@s1, 0)
    open_sale!(@s2, 55_000)
    sign_in(@buyer)
    get billing_checkout_path(@s2.product.code)
    assert_select "form[action=?]", billing_orders_path
    assert_includes css_select("main").text, "55,000원"
    assert_select "#season-free-start", 0
  end

  test "the panel warns when the global commerce switch is off" do
    ENV["LEEDOX_COMMERCE_ENABLED"] = "false"
    sign_in(@admin)
    get edit_admin_product_season_path(@s1)
    assert_includes css_select("#sale-settings").text, "LEEDOX_COMMERCE_ENABLED"
  end

  # --- customer Season page -------------------------------------------------

  test "a Season with no price stays free and public exactly as before" do
    get product_season_path(@line.slug, @s1.slug)
    assert_response :success
    assert_select "#season-purchase", 0
    get product_season_episode_path(@line.slug, @s1.slug, "01")
    assert_response :success
    assert_match(/S01 유료 본문/, response.body)
    get product_season_episode_asset_path(@line.slug, @s1.slug, "01", @asset.id)
    assert_response :success
  end

  test "purchase box: shows price and 구매하기 when on sale, 'not available' when stopped, and 'owned' for the buyer" do
    Commerce::SeasonSales.set_price!(season: @s1, total_amount: 33_000, actor: @admin)
    get product_season_path(@line.slug, @s1.slug)
    assert_select "#season-purchase"
    assert_includes css_select("#season-purchase").text, "현재 구매할 수 없습니다"
    assert_select "#season-purchase a", 0

    Commerce::SeasonSales.start_sale!(season: @s1, actor: @admin)
    get product_season_path(@line.slug, @s1.slug)
    assert_includes css_select("#season-purchase").text, "33,000원"
    assert_includes css_select("#season-purchase").text, "한 번 결제 · 무기한 이용"
    assert_select "#season-purchase a[href=?]", billing_checkout_path(@s1.reload.product.code), text: "구매하기"
    assert_includes css_select("#season-purchase a").first["class"].split, "whitespace-nowrap"

    buy!(@buyer, @s1)
    sign_in(@buyer)
    get product_season_path(@line.slug, @s1.slug)
    assert_includes css_select("#season-purchase").text, "구매한 Season입니다 · 무기한 이용"
    assert_select "#season-purchase a", 0
  end

  # --- gating ---------------------------------------------------------------

  test "paid Season: episodes and files need a license -- guests sign in, non-owners go to the purchase box, owners get in" do
    open_sale!(@s1)
    episode = product_season_episode_path(@line.slug, @s1.slug, "01")
    download = product_season_episode_asset_path(@line.slug, @s1.slug, "01", @asset.id)

    get episode
    assert_redirected_to new_user_session_path
    get download
    assert_redirected_to new_user_session_path

    sign_in(@other)
    get episode
    assert_redirected_to product_season_path(@line.slug, @s1.slug)
    assert_no_match(/S01 유료 본문/, response.body)
    get download
    assert_redirected_to product_season_path(@line.slug, @s1.slug)
    follow_redirect!
    assert_match(/구매하면 볼 수 있습니다/, response.body)
    assert_no_match(/S01 소스/, response.body, "file list is hidden from non-owners")
    sign_out

    buy!(@buyer, @s1)
    sign_in(@buyer)
    get episode
    assert_response :success
    assert_match(/S01 유료 본문/, response.body)
    get download
    assert_response :success
    assert_match(/\Aattachment;/, response.headers["Content-Disposition"])
    get product_season_path(@line.slug, @s1.slug)
    assert_select "h2", text: "Season 산출물"
  end

  test "the Season list page stays public even when paid (titles are the storefront)" do
    open_sale!(@s1)
    get product_season_path(@line.slug, @s1.slug)
    assert_response :success
    assert_includes css_select("main").text, "S01 첫 편"
  end

  test "S01 owner is locked out of S02, and each Season's lifecycle gates still apply on top of the license" do
    open_sale!(@s1)
    open_sale!(@s2, 55_000)
    buy!(@buyer, @s1)
    sign_in(@buyer)

    get product_season_episode_path(@line.slug, @s2.slug, "01")
    assert_redirected_to product_season_path(@line.slug, @s2.slug)
    assert_no_match(/S02 유료 본문/, response.body)

    @s1.update!(visibility: "private")
    get product_season_episode_path(@line.slug, @s1.slug, "01")
    assert_response :not_found, "a private Season is unreachable even for its owner (lifecycle gate first)"
    @s1.update!(visibility: "public")
    @ep1.update!(status: "draft")
    get product_season_episode_path(@line.slug, @s1.slug, "01")
    assert_response :not_found
  end

  test "after the sale is stopped an owner still reads and downloads; a refund then takes it away" do
    open_sale!(@s1)
    order = buy!(@buyer, @s1)
    Commerce::SeasonSales.stop_sale!(season: @s1, actor: @admin)

    sign_in(@buyer)
    get product_season_episode_path(@line.slug, @s1.slug, "01")
    assert_response :success
    get product_season_episode_asset_path(@line.slug, @s1.slug, "01", @asset.id)
    assert_response :success

    request = Commerce::RefundRequestSubmission.call!(user: @buyer, order: order, reason_code: "other", customer_note: "환불")
    %w[start_review approve mark_processing].each { |a| Commerce::RefundRequestTransition.call!(refund_request: request, actor: @admin, action: a) }
    Commerce::ConfirmRefund.call!(refund_request: request.reload, actor: @admin)

    get product_season_episode_path(@line.slug, @s1.slug, "01")
    assert_redirected_to product_season_path(@line.slug, @s1.slug)
    get product_season_episode_asset_path(@line.slug, @s1.slug, "01", @asset.id)
    assert_redirected_to product_season_path(@line.slug, @s1.slug)
  end

  # --- checkout ---------------------------------------------------------------

  test "checkout requires login, shows a one-time price with no start date or period, and the order becomes an indefinite license after admin confirmation" do
    open_sale!(@s1)
    code = @s1.product.code

    get billing_checkout_path(code)
    assert_redirected_to new_user_session_path

    sign_in(@buyer)
    get billing_checkout_path(code)
    assert_response :success
    assert_includes css_select("main").text, "33,000원"
    assert_includes css_select("main").text, "무기한 이용"
    assert_select "input[name='order[requested_start_on]']", 0
    assert_select "input[type=hidden][name='order[offer_code]'][value=?]", @s1.lifetime_offer.code
    assert_no_match(/개월|서비스 시작일/, css_select("main").text)

    assert_difference [ "Order.count", "OrderItem.count" ], 1 do
      post billing_orders_path, params: { order: { product_code: code, offer_code: @s1.lifetime_offer.code, payment_method: "manual" } }
    end
    order = Order.order(:created_at).last
    assert_redirected_to billing_order_path(order.public_id)
    follow_redirect!
    assert_response :success
    assert_includes css_select("main").text, "무기한 (한 번 결제)"
    assert_includes css_select("main").text, "33,000원"
    assert_no_match(/마지막 이용일|\d+개월/, css_select("main").text)
    assert_select "h1", text: /주문이 접수되었습니다/

    get product_season_episode_path(@line.slug, @s1.slug, "01")
    assert_redirected_to product_season_path(@line.slug, @s1.slug), "not yet confirmed -> still locked"
    sign_out

    sign_in(@admin)
    get admin_commerce_order_path(order.public_id)
    assert_response :success
    assert_no_match(/개월/, css_select("main").text.gsub("무기한", ""))
    assert_difference "License.count", 1 do
      post confirm_manual_payment_admin_commerce_order_path(order.public_id)
    end
    get admin_commerce_order_path(order.public_id)
    assert_includes css_select("main").text, "무기한"
    sign_out

    sign_in(@buyer)
    get product_season_episode_path(@line.slug, @s1.slug, "01")
    assert_response :success
    get mypage_path
    assert_response :success
    assert_includes response.body, "무기한"
    get dashboard_path
    assert_response :success
  end

  test "checkout for an owned Season, a stopped Season and a duplicate order" do
    open_sale!(@s1)
    code = @s1.product.code
    buy!(@buyer, @s1)
    sign_in(@buyer)
    get billing_checkout_path(code)
    assert_select "#season-already-owned"
    assert_select "form[action=?]", billing_orders_path, 0
    assert_no_difference "Order.count" do
      post billing_orders_path, params: { order: { product_code: code, offer_code: @s1.lifetime_offer.code, payment_method: "manual" } }
    end
    assert_redirected_to billing_checkout_path(code)

    sign_out
    sign_in(@other)
    Commerce::SeasonSales.stop_sale!(season: @s1, actor: @admin)
    get billing_checkout_path(code)
    assert_response :success
    assert_select "form[action=?]", billing_orders_path, 0
    assert_no_difference "Order.count" do
      post billing_orders_path, params: { order: { product_code: code, offer_code: @s1.lifetime_offer.code, payment_method: "manual" } }
    end
  end

  test "a customer's pending one-time order can be retried without hitting the period code" do
    open_sale!(@s1)
    order = Commerce::OrderCreator.call!(user: @buyer, product_code: @s1.product.code, offer_code: @s1.lifetime_offer.code, requested_start_on: nil, provider: "manual")
    order.transition_to!("abandoned", abandoned_at: Time.current, finalized_at: Time.current)
    sign_in(@buyer)
    get retry_billing_order_path(order.public_id)
    assert_response :success
    assert_includes css_select("main").text, "무기한"
  end

  # --- isolation from the four term products ----------------------------------

  test "Season products never appear in the term-product catalog, dashboards or admin grants" do
    open_sale!(@s1)
    name = @s1.product.name
    buy!(@buyer, @s1)

    get pricing_path
    assert_response :success
    assert_no_match(/#{Regexp.escape(name)}/, response.body)
    get root_path
    assert_no_match(/#{Regexp.escape(name)}/, response.body)

    sign_in(@buyer)
    get dashboard_path
    assert_response :success
    assert_no_match(/#{Regexp.escape(name)}/, css_select("main").text.sub(/무기한.*/m, ""))
    sign_out

    sign_in(@admin)
    get admin_users_path
    assert_response :success
    assert_no_match(/#{Regexp.escape(name)}/, css_select("main").text.split("구매자").first.to_s)
    get admin_commerce_products_path
    assert_response :success
    assert_no_match(/#{Regexp.escape(@s1.product.code)}/, response.body)
    post grant_free_license_admin_user_path(@other), params: { product_code: @s1.product.code }
    assert_no_difference "License.count" do
      post grant_free_license_admin_user_path(@other), params: { product_code: @s1.product.code }
    end
  end

  test "the four term products still sell and grant finite licenses as before" do
    Product.find_by!(code: "chatdox").update!(sale_enabled: true)
    sign_in(@buyer)
    get billing_checkout_path("chatdox")
    assert_response :success
    assert_select "input[name='order[requested_start_on]']"
    assert_includes css_select("main").text, "개월"
    get pricing_path
    assert_match(/Chatdox/, response.body)
  end
end
