require "test_helper"

class CommerceConfirmRefundTest < ActiveSupport::TestCase
  KST = Commerce::PeriodCalculator::KST

  setup do
    Commerce::CatalogBootstrap.call!
    @previous_flag = ENV["LEEDOX_COMMERCE_ENABLED"]
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    Product.find_by!(code: "chatdox").update!(sale_enabled: true)
    @admin = User.create!(name: "관리자", email: "confirm-refund-admin@example.com", password: "password123", role: :admin)
    @buyer = User.create!(name: "구매자", email: "confirm-refund-buyer@example.com", password: "password123")
    @order = Commerce::OrderCreator.call!(
      user: @buyer, product_code: "chatdox", offer_code: "chatdox-1m-v1",
      requested_start_on: Time.current.in_time_zone(KST).to_date, provider: "portone"
    )
    Commerce::OrderFinalizer.call!(
      order: @order,
      payment: {
        provider: "portone", provider_payment_id: "pp-#{@order.public_id}", order_id: @order.public_id,
        amount: @order.total_amount, currency: @order.currency, provider_payload: { "status" => "PAID" }
      }
    )
    @refund_request = Commerce::RefundRequestSubmission.call!(
      user: @buyer, order: @order.reload, reason_code: "before_service_start", customer_note: "테스트"
    )
  end

  teardown do
    @previous_flag.nil? ? ENV.delete("LEEDOX_COMMERCE_ENABLED") : ENV["LEEDOX_COMMERCE_ENABLED"] = @previous_flag
  end

  test "confirming a refund in 'processing' cancels the order's license and records provider confirmation" do
    Commerce::RefundRequestTransition.call!(refund_request: @refund_request, actor: @admin, action: "start_review")
    Commerce::RefundRequestTransition.call!(refund_request: @refund_request, actor: @admin, action: "approve")
    Commerce::RefundRequestTransition.call!(refund_request: @refund_request, actor: @admin, action: "mark_processing")

    license = @order.licenses.sole
    assert_equal "active", license.status

    Commerce::ConfirmRefund.call!(refund_request: @refund_request.reload, actor: @admin)

    @refund_request.reload
    assert_equal "refunded", @refund_request.status
    assert @refund_request.external_refund_confirmed?
    assert_equal "confirmed", @refund_request.provider_refund_status
    assert_not_nil @refund_request.external_processed_at

    assert_equal "canceled", license.reload.status
    assert_not Entitlements::ProductAccess.licensed?(user: @buyer, product_code: "chatdox")

    audit = @refund_request.commerce_audit_events.find_by!(action: "refund_confirmed")
    assert_equal @admin, audit.actor
    assert_equal %w[processing refunded], [ audit.from_state, audit.to_state ]
  end

  test "confirming a refund that is not in 'processing' is rejected" do
    assert_equal "requested", @refund_request.status

    assert_raises(Commerce::ConfirmRefund::Unavailable) do
      Commerce::ConfirmRefund.call!(refund_request: @refund_request, actor: @admin)
    end
    assert_equal "requested", @refund_request.reload.status
    assert_equal "active", @order.licenses.sole.reload.status
  end

  test "a non-admin cannot confirm a refund" do
    Commerce::RefundRequestTransition.call!(refund_request: @refund_request, actor: @admin, action: "start_review")
    Commerce::RefundRequestTransition.call!(refund_request: @refund_request, actor: @admin, action: "approve")
    Commerce::RefundRequestTransition.call!(refund_request: @refund_request, actor: @admin, action: "mark_processing")

    assert_raises(Pundit::NotAuthorizedError) do
      Commerce::ConfirmRefund.call!(refund_request: @refund_request.reload, actor: @buyer)
    end
    assert_equal "active", @order.licenses.sole.reload.status
  end

  test "a second refund request is rejected once the first one is confirmed refunded (mypage display bug companion)" do
    Commerce::RefundRequestTransition.call!(refund_request: @refund_request, actor: @admin, action: "start_review")
    Commerce::RefundRequestTransition.call!(refund_request: @refund_request, actor: @admin, action: "approve")
    Commerce::RefundRequestTransition.call!(refund_request: @refund_request, actor: @admin, action: "mark_processing")
    Commerce::ConfirmRefund.call!(refund_request: @refund_request.reload, actor: @admin)

    assert_raises(Commerce::RefundRequestSubmission::Unavailable) do
      Commerce::RefundRequestSubmission.call!(user: @buyer, order: @order.reload, reason_code: "other", customer_note: nil)
    end
  end

  test "mark_failed transitions to failed without touching the license" do
    Commerce::RefundRequestTransition.call!(refund_request: @refund_request, actor: @admin, action: "start_review")
    Commerce::RefundRequestTransition.call!(refund_request: @refund_request, actor: @admin, action: "approve")
    Commerce::RefundRequestTransition.call!(refund_request: @refund_request, actor: @admin, action: "mark_processing")

    Commerce::RefundRequestTransition.call!(refund_request: @refund_request.reload, actor: @admin, action: "mark_failed")

    @refund_request.reload
    assert_equal "failed", @refund_request.status
    assert_equal "failed", @refund_request.provider_refund_status
    assert_not @refund_request.external_refund_confirmed?
    assert_equal "active", @order.licenses.sole.reload.status
  end
end
