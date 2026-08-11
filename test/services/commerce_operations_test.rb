require "test_helper"

class CommerceOperationsTest < ActiveSupport::TestCase
  KST = Commerce::PeriodCalculator::KST

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
    @buyer = User.create!(name: "테스트 유저", email: "operations-buyer@example.com", password: "password123", created_at: 30.days.ago)
    @admin = User.create!(name: "테스트 유저", email: "operations-admin@example.com", password: "password123", role: :admin, created_at: 30.days.ago)
    @at = KST.local(2026, 7, 15, 12)
  end

  teardown do
    @previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "pending assessment separates fresh and stale and only allows evidence-free pending orders" do
    fresh = create_order(at: @at)
    stale = create_order(at: @at - 31.minutes)
    provider_known = create_order(at: @at - 31.minutes)
    provider_known.payment_transaction.update!(provider_payment_id: "known-provider-id")
    success_possible = create_order(at: @at - 31.minutes)
    success_possible.payment_transaction.update!(provider_status: "PAID", provider_observed_at: @at)

    assert_equal "fresh", Commerce::PendingOrderAssessment.call(order: fresh, at: @at).classification
    assert_not Commerce::PendingOrderAssessment.call(order: fresh, at: @at).safe_to_abandon
    assert Commerce::PendingOrderAssessment.call(order: stale, at: @at).safe_to_abandon
    assert Commerce::PendingOrderAssessment.call(order: provider_known, at: @at).provider_confirmation_required
    assert Commerce::PendingOrderAssessment.call(order: success_possible, at: @at).success_evidence
  end

  test "abandon locks and audits only a safe stale order" do
    safe = create_order(at: @at - 31.minutes)
    unsafe = create_order(at: @at - 31.minutes)
    unsafe.payment_transaction.update!(provider_status: "PAID")

    assert_raises(Pundit::NotAuthorizedError) do
      Commerce::AbandonOrder.call!(order: safe, actor: @buyer, at: @at)
    end
    assert_equal "pending", safe.reload.status

    Commerce::AbandonOrder.call!(order: safe, actor: @admin, at: @at)

    assert_equal "abandoned", safe.reload.status
    assert_equal @at, safe.abandoned_at
    audit = safe.commerce_audit_events.find_by!(action: "order_abandoned")
    assert_equal @admin, audit.actor
    assert_equal [ "pending", "abandoned" ], [ audit.from_state, audit.to_state ]
    assert_raises(Commerce::AbandonOrder::Unsafe) do
      Commerce::AbandonOrder.call!(order: unsafe, actor: @admin, at: @at)
    end
    assert_equal "pending", unsafe.reload.status
  end

  test "late provider success remains an abandoned conflict without creating a license" do
    order = create_order(at: @at - 31.minutes)
    Commerce::AbandonOrder.call!(order: order, actor: @admin, at: @at)

    assert_no_difference "License.count" do
      Commerce::OrderFinalizer.call!(order: order, payment: payment_for(order), at: @at + 1.minute)
    end

    assert_equal "abandoned", order.reload.status
    assert_equal "PAID", order.payment_transaction.reload.provider_status
    assert order.commerce_audit_events.exists?(action: "late_provider_success_observed")
    report = Commerce::Reconciliation.call(at: @at + 2.minutes, log: false)
    assert_includes report.issues.map(&:code), "abandoned_provider_success_conflict"
  end

  test "retry creates one new order from the current offer and keeps its source" do
    source = create_order(at: @at - 31.minutes)
    original_total = source.total_amount
    offer = @product.product_offers.find_by!(duration_months: 1)
    offer.update!(supply_amount: 8_000, vat_amount: 800, total_amount: 8_800)

    assert_difference "Order.count", 1 do
      first = Commerce::RetryOrder.call!(source_order: source, user: @buyer, provider: "portone", at: @at)
      second = Commerce::RetryOrder.call!(source_order: source.reload, user: @buyer, provider: "portone", at: @at)
      assert_equal first, second
    end

    retry_order = source.reload.retry_order
    assert_equal source, retry_order.retry_of_order
    assert_equal 8_800, retry_order.total_amount
    assert_equal original_total, source.total_amount
    assert retry_order.commerce_audit_events.exists?(action: "retry_order_created", actor: @buyer)
  end

  test "order creation is rejected once the license chain would start more than 12 months out (handoff 0043)" do
    License.create!(
      user: @buyer, product: @product, source: "coupon", status: "scheduled",
      starts_on: @at.to_date, last_usable_on: @at.to_date + 13.months,
      access_ends_at: KST.local(*(@at.to_date + 13.months + 1.day).then { |d| [ d.year, d.month, d.day ] })
    )

    assert_raises(Commerce::OrderCreator::Unavailable) { create_order(at: @at) }
  end

  test "retrying an order is rejected the same way once the license chain has grown past 12 months out" do
    source = create_order(at: @at - 31.minutes)
    License.create!(
      user: @buyer, product: @product, source: "coupon", status: "scheduled",
      starts_on: @at.to_date, last_usable_on: @at.to_date + 13.months,
      access_ends_at: KST.local(*(@at.to_date + 13.months + 1.day).then { |d| [ d.year, d.month, d.day ] })
    )

    assert_raises(Commerce::OrderCreator::Unavailable) do
      Commerce::RetryOrder.call!(source_order: source, user: @buyer, provider: "portone", at: @at)
    end
  end

  test "retry remains closed with the commerce gate disabled" do
    source = create_order(at: @at - 31.minutes)
    ENV["LEEDOX_COMMERCE_ENABLED"] = "false"

    assert_no_difference "Order.count" do
      assert_raises(Commerce::OrderCreator::Unavailable) do
        Commerce::RetryOrder.call!(source_order: source, user: @buyer, provider: "portone", at: @at)
      end
    end
  end

  test "refund submission and review never mutate payment order or license" do
    order = finalized_order
    original = [ order.status, order.payment_transaction.status, order.licenses.pluck(:id, :status, :starts_on, :last_usable_on) ]

    request = Commerce::RefundRequestSubmission.call!(
      user: @buyer,
      order: order,
      reason_code: "service_issue",
      customer_note: "검토를 요청합니다.",
      at: @at
    )
    assert_equal order.total_amount, request.requested_amount
    assert request.full_request?
    assert request.commerce_audit_events.exists?(action: "refund_requested", actor: @buyer)
    assert_raises(Commerce::RefundRequestSubmission::Unavailable) do
      Commerce::RefundRequestSubmission.call!(user: @buyer, order: order, reason_code: "other", customer_note: nil)
    end

    Commerce::RefundRequestTransition.call!(refund_request: request, actor: @admin, action: "start_review", internal_note: "내부 검토", at: @at + 1.minute)
    Commerce::RefundRequestTransition.call!(refund_request: request, actor: @admin, action: "approve", public_response: "승인 검토 결과", at: @at + 2.minutes)
    Commerce::RefundRequestTransition.call!(refund_request: request, actor: @admin, action: "mark_processing", at: @at + 3.minutes)

    assert_equal "processing", request.reload.status
    assert_equal "pending", request.provider_refund_status
    assert_not request.external_refund_confirmed?
    assert_equal original, [ order.reload.status, order.payment_transaction.reload.status, order.licenses.pluck(:id, :status, :starts_on, :last_usable_on) ]
  end

  test "invalid refund transitions and non-owner submissions are rejected" do
    order = finalized_order
    other = User.create!(name: "테스트 유저", email: "operations-other@example.com", password: "password123")
    request = Commerce::RefundRequestSubmission.call!(user: @buyer, order: order, reason_code: "other", customer_note: nil)

    assert_raises(Pundit::NotAuthorizedError) do
      Commerce::RefundRequestSubmission.call!(user: other, order: order, reason_code: "other", customer_note: nil)
    end
    assert_raises(ArgumentError) do
      Commerce::RefundRequestTransition.call!(refund_request: request, actor: @admin, action: "approve")
    end
    assert_raises(Pundit::NotAuthorizedError) do
      Commerce::RefundRequestTransition.call!(refund_request: request, actor: @buyer, action: "start_review")
    end
  end

  private

  def create_order(at: @at)
    Commerce::OrderCreator.call!(
      user: @buyer,
      product_code: "chatdox",
      offer_code: "chatdox-1m-v1",
      requested_start_on: at.in_time_zone(KST).to_date,
      provider: "portone",
      at: at
    )
  end

  def finalized_order
    order = create_order
    Commerce::OrderFinalizer.call!(order: order, payment: payment_for(order), at: @at)
  end

  def payment_for(order)
    {
      provider: "portone",
      provider_payment_id: "provider-payment-#{order.public_id}",
      order_id: order.public_id,
      amount: order.total_amount,
      currency: order.currency,
      provider_payload: { "status" => "PAID" }
    }
  end
end
