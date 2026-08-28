require "test_helper"

class CommerceOperationsAccessTest < ActionDispatch::IntegrationTest
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
    @product.update!(sale_enabled: true)
    @admin = User.create!(name: "테스트 유저", email: "commerce-admin@example.com", password: "password123", role: :admin)
    @buyer = User.create!(name: "테스트 유저", email: "commerce-buyer@example.com", password: "password123", created_at: 30.days.ago)
    @other = User.create!(name: "테스트 유저", email: "commerce-other@example.com", password: "password123", created_at: 30.days.ago)
    @at = Time.current.change(usec: 0)
  end

  teardown do
    @previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "admin order pages require admin authentication and expose no sensitive provider data" do
    order = finalized_order(@buyer, payload: { "status" => "PAID", "cardNumber" => "sensitive-card", "secret" => "sensitive-secret" })

    get admin_commerce_orders_path
    assert_redirected_to new_user_session_path

    sign_in(@buyer)
    get admin_commerce_orders_path
    assert_redirected_to root_path

    delete destroy_user_session_path
    sign_in(@admin)
    get admin_commerce_orders_path
    assert_response :success
    get admin_commerce_order_path(order.public_id)
    assert_response :success
    assert_match(/Transaction · License · Refund/, response.body)
    assert_no_match(/sensitive-card|sensitive-secret|provider_payload|provider-payment-/, response.body)
  end

  test "admin filters status product provider date and pending age" do
    stale = create_order(@buyer, at: @at - 31.minutes)
    paid = finalized_order(@buyer)
    sign_in(@admin)

    get admin_commerce_orders_path, params: {
      status: "pending", product: "chatdox", provider: "portone", pending_age: "stale",
      from: (@at.to_date - 1.day).iso8601, to: @at.to_date.iso8601
    }

    assert_response :success
    assert_match stale.public_id.first(8), response.body
    assert_match(/stale/, response.body)
    assert_no_match paid.public_id.first(8), response.body
  end

  test "admin list uses eager loading without per-order query growth" do
    3.times { |index| create_order(@buyer, at: @at - (31 + index).minutes) }
    sign_in(@admin)

    count = select_query_count { get admin_commerce_orders_path }

    assert_response :success
    assert_operator count, :<=, 25
  end

  test "customer refund IDOR and mass assignment are rejected while internal notes stay private" do
    own_order = finalized_order(@buyer)
    other_order = finalized_order(@other)
    sign_in(@buyer)

    get new_billing_order_refund_request_path(other_order.public_id)
    assert_response :not_found

    assert_difference [ "RefundRequest.count", "CommerceAuditEvent.count" ], 1 do
      post billing_order_refund_requests_path(own_order.public_id), params: {
        refund_request: {
          reason_code: "service_issue",
          customer_note: "<script>alert(1)</script>",
          requested_amount: 1,
          status: "refunded",
          processed_by_id: @admin.id,
          external_refund_confirmed: true
        }
      }
    end
    request_record = RefundRequest.order(:created_at).last
    assert_equal own_order.total_amount, request_record.requested_amount
    assert_equal "requested", request_record.status
    assert_nil request_record.processed_by
    assert_not request_record.external_refund_confirmed?

    request_record.update!(internal_note: "customer-must-not-see-this")
    get refund_request_path(request_record.public_id)
    assert_response :success
    assert_match(/&lt;script&gt;alert\(1\)&lt;\/script&gt;/, response.body)
    assert_no_match(/customer-must-not-see-this/, response.body)
  end

  test "refund requests are limited to the owners paid order and one open request" do
    pending = create_order(@buyer)
    paid = finalized_order(@buyer)
    sign_in(@buyer)

    assert_no_difference "RefundRequest.count" do
      post billing_order_refund_requests_path(pending.public_id), params: { refund_request: { reason_code: "other" } }
    end
    assert_difference "RefundRequest.count", 1 do
      post billing_order_refund_requests_path(paid.public_id), params: { refund_request: { reason_code: "other" } }
    end
    assert_no_difference "RefundRequest.count" do
      post billing_order_refund_requests_path(paid.public_id), params: { refund_request: { reason_code: "other" } }
    end
  end

  test "full admin refund review through confirm_refunded cancels the license via the real controller/routes" do
    order = finalized_order(@buyer)
    request_record = Commerce::RefundRequestSubmission.call!(user: @buyer, order: order, reason_code: "other", customer_note: nil)
    sign_in(@admin)

    patch admin_commerce_refund_request_path(request_record.public_id), params: { refund_request: { action_name: "start_review" } }
    patch admin_commerce_refund_request_path(request_record.public_id), params: { refund_request: { action_name: "approve" } }
    patch admin_commerce_refund_request_path(request_record.public_id), params: { refund_request: { action_name: "mark_processing" } }
    assert_equal "processing", request_record.reload.status

    patch admin_commerce_refund_request_path(request_record.public_id), params: { refund_request: { action_name: "confirm_refunded" } }
    assert_redirected_to admin_commerce_refund_request_path(request_record.public_id)

    request_record.reload
    assert_equal "refunded", request_record.status
    assert request_record.external_refund_confirmed?
    assert_equal "canceled", order.licenses.sole.reload.status
    assert_not Entitlements::ProductAccess.licensed?(user: @buyer, product_code: "chatdox")

    # mypage's order status badge and refund link both have to read the
    # refund outcome, not just Order#status (which stays "paid" forever --
    # there's no "refunded" order status). Before this fix, a refunded order
    # kept showing "결제 완료" and offered a fresh "환불 요청" link.
    delete destroy_user_session_path
    sign_in(@buyer)
    get mypage_path
    assert_response :success
    assert_match(/환불 완료/, response.body)
    assert_no_match(/결제 완료/, response.body)
    assert_select "a", text: "환불 내역 보기"
    assert_select "a", text: "환불 요청", count: 0
  end

  test "admin review rejects state spoofing and approval leaves order payment and license unchanged" do
    order = finalized_order(@buyer)
    request_record = Commerce::RefundRequestSubmission.call!(user: @buyer, order: order, reason_code: "other", customer_note: nil)
    original = [ order.status, order.payment_transaction.status, order.licenses.pluck(:id, :status) ]
    sign_in(@admin)

    patch admin_commerce_refund_request_path(request_record.public_id), params: {
      refund_request: { action_name: "refunded", external_refund_confirmed: true, status: "refunded" }
    }
    assert_redirected_to admin_commerce_refund_request_path(request_record.public_id)
    assert_equal "requested", request_record.reload.status

    patch admin_commerce_refund_request_path(request_record.public_id), params: { refund_request: { action_name: "start_review", internal_note: "internal-only" } }
    patch admin_commerce_refund_request_path(request_record.public_id), params: { refund_request: { action_name: "approve", public_response: "검토 승인" } }
    assert_equal "approved", request_record.reload.status
    assert_equal original, [ order.reload.status, order.payment_transaction.reload.status, order.licenses.pluck(:id, :status) ]
    assert request_record.commerce_audit_events.exists?(action: "refund_approved", actor: @admin)
  end

  test "retry endpoint is owner scoped idempotent and closed by the sales gate" do
    stale = create_order(@buyer, at: @at - 31.minutes)
    other_stale = create_order(@other, at: @at - 31.minutes)
    sign_in(@buyer)

    post create_retry_billing_order_path(other_stale.public_id)
    assert_response :not_found

    assert_difference "Order.count", 1 do
      2.times do
        post create_retry_billing_order_path(stale.public_id)
        assert_response :redirect
      end
    end
    assert_equal stale.reload.retry_order, Order.order(:created_at).last

    gated = create_order(@buyer, at: @at - 31.minutes)
    ENV["LEEDOX_COMMERCE_ENABLED"] = "false"
    assert_no_difference "Order.count" do
      post create_retry_billing_order_path(gated.public_id)
      assert_redirected_to billing_checkout_path
    end
  end

  test "resubmitting checkout redirects to the same pending order instead of piling up duplicates" do
    sign_in(@buyer)

    assert_difference "Order.count", 1 do
      post billing_orders_path, params: { order: { product_code: "chatdox", offer_code: "chatdox-1m-v1", requested_start_on: @at.to_date.iso8601 } }
    end
    first_redirect = response.location

    assert_no_difference "Order.count" do
      post billing_orders_path, params: { order: { product_code: "chatdox", offer_code: "chatdox-1m-v1", requested_start_on: @at.to_date.iso8601 } }
    end
    assert_equal first_redirect, response.location
  end

  test "admin dashboard and refund requests index surface open refund requests (handoff 0051 R2-1)" do
    order = finalized_order(@buyer)
    request_record = Commerce::RefundRequestSubmission.call!(user: @buyer, order: order, reason_code: "other", customer_note: nil)
    sign_in(@admin)

    get admin_dashboard_path
    assert_response :success
    assert_match(/환불 대기 1건 검토가 필요합니다/, response.body)

    get admin_commerce_refund_requests_path
    assert_response :success
    assert_select "a[href=?]", admin_commerce_refund_request_path(request_record.public_id), text: "검토하기"

    Commerce::RefundRequestTransition.call!(refund_request: request_record, actor: @admin, action: "start_review")
    Commerce::RefundRequestTransition.call!(refund_request: request_record, actor: @admin, action: "approve")
    Commerce::RefundRequestTransition.call!(refund_request: request_record, actor: @admin, action: "mark_processing")
    Commerce::ConfirmRefund.call!(refund_request: request_record.reload, actor: @admin)

    get admin_dashboard_path
    assert_no_match(/환불 대기 \d+건 검토가 필요합니다/, response.body)
    get admin_commerce_refund_requests_path
    assert_select "a", text: "검토하기", count: 0
  end

  test "mypage shows order date/id/payment method/license period and hides the refund link once the license has expired (handoff 0051 R2-2/R2-3)" do
    order = finalized_order(@buyer)
    order.licenses.sole.update_columns(
      starts_on: 40.days.ago.to_date, last_usable_on: 10.days.ago.to_date, access_ends_at: 9.days.ago
    )
    sign_in(@buyer)

    reference = order.public_id.delete("-").first(8).upcase
    get mypage_path
    assert_response :success
    assert_match(/주문번호 #{Regexp.escape(reference)}/, response.body)
    assert_match(/카카오페이/, response.body)
    assert_match(/이용 기간/, response.body)
    assert_select "a", text: "환불 요청", count: 0
    assert_match(/이용이 끝난 건은 환불이 제한됩니다/, response.body)
  end

  test "mypage paginates orders past the first 10 instead of hiding older ones entirely (handoff 0051 R2-2)" do
    11.times { finalized_order(@buyer) }
    sign_in(@buyer)

    get mypage_path
    assert_response :success
    assert_select "li.py-3", count: 10
    assert_select "a", text: "다음 →"
    assert_select "a", text: "← 이전", count: 0

    get mypage_path(orders_page: 2)
    assert_response :success
    assert_select "li.py-3", count: 1
    assert_select "a", text: "← 이전"
  end

  private

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def create_order(user, at: @at)
    Commerce::OrderCreator.call!(
      user: user,
      product_code: "chatdox",
      offer_code: "chatdox-1m-v1",
      requested_start_on: at.in_time_zone(Commerce::PeriodCalculator::KST).to_date,
      provider: "portone",
      at: at
    )
  end

  def finalized_order(user, payload: { "status" => "PAID" })
    order = create_order(user)
    Commerce::OrderFinalizer.call!(
      order: order,
      payment: {
        provider: "portone",
        provider_payment_id: "provider-payment-#{order.public_id}",
        order_id: order.public_id,
        amount: order.total_amount,
        currency: order.currency,
        provider_payload: payload
      },
      at: @at
    )
  end

  def select_query_count
    count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      count += 1 if sql.start_with?("SELECT") && !sql.include?("schema_migrations")
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end
end
