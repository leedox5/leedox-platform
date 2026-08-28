require "test_helper"

class CommerceReconciliationTest < ActiveSupport::TestCase
  KST = Commerce::PeriodCalculator::KST

  setup do
    Commerce::CatalogBootstrap.call!
    @previous_flag = ENV["LEEDOX_COMMERCE_ENABLED"]
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    @product = Product.find_by!(code: "chatdox")
    @product.update!(sale_enabled: true)
    @offer = @product.product_offers.find_by!(code: "chatdox-1m-v1")
    @at = Time.current.change(usec: 0)
    @sequence = 0
  end

  teardown do
    @previous_flag.nil? ? ENV.delete("LEEDOX_COMMERCE_ENABLED") : ENV["LEEDOX_COMMERCE_ENABLED"] = @previous_flag
  end

  test "normal finalized order has no reconciliation issue and the scan is read only" do
    order = create_order
    Commerce::OrderFinalizer.call!(order: order, payment: payment_for(order), at: @at)
    before = database_snapshot

    report = Commerce::Reconciliation.call(at: @at + 1.minute, log: false)

    assert report.ok?
    assert_empty report.issues
    assert_equal before, database_snapshot
  end

  test "reconciliation detects every required anomaly without changing data" do
    paid_without_transaction = finalized_order
    paid_without_transaction.payment_transaction.destroy!

    paid_without_license = finalized_order
    License.where(order_item_id: paid_without_license.order_item_ids).delete_all

    create_order(at: @at - 2.hours)

    terminal_with_license = finalized_order
    terminal_with_license.update_columns(status: "failed")

    amount_mismatch = create_order
    amount_mismatch.payment_transaction.update_column(:amount, 1)

    item_mismatch = create_order
    item_mismatch.order_items.first.update_column(:total_amount, 1)

    create_overlapping_licenses

    processed_unfinalized = create_order
    processed_unfinalized.payment_transaction.update!(
      status: "active",
      provider_payment_id: "processed-#{processed_unfinalized.public_id}",
      provider_payload: { "status" => "DONE" }
    )

    before = database_snapshot
    report = Commerce::Reconciliation.call(stale_after: 30.minutes, at: @at, log: false)
    codes = report.issues.map(&:code)

    %w[
      paid_without_transaction paid_without_license stale_pending
      terminal_order_with_license payment_amount_mismatch
      order_item_total_mismatch overlapping_license
      processed_payment_unfinalized
    ].each { |code| assert_includes codes, code }
    assert_not report.ok?
    assert_equal before, database_snapshot
    assert report.issues.all? { |issue| issue.order_public_id.present? }
  end

  test "reconciliation reports pending summary and refund operation anomalies read only" do
    create_order(at: @at - 2.hours)
    create_order(at: @at)

    paid_with_open_refund = finalized_order
    Commerce::RefundRequestSubmission.call!(
      user: paid_with_open_refund.user,
      order: paid_with_open_refund,
      reason_code: "other",
      customer_note: nil,
      at: @at
    )

    refunded_without_confirmation = finalized_order
    first_refund = create_refunded_request(refunded_without_confirmation, confirmed: false)
    assert_not first_refund.external_refund_confirmed?

    refunded_with_license = finalized_order
    create_refunded_request(refunded_with_license, confirmed: true)

    abandoned_conflict = create_order(at: @at - 2.hours)
    abandoned_conflict.update_columns(status: "abandoned", abandoned_at: @at, finalized_at: @at)
    abandoned_conflict.payment_transaction.update!(provider_status: "PAID", provider_observed_at: @at)

    before = database_snapshot
    report = Commerce::Reconciliation.call(stale_after: 30.minutes, at: @at, log: false)
    codes = report.issues.map(&:code)

    assert_equal({ fresh: 1, stale: 1 }, report.pending_summary)
    assert_includes codes, "paid_order_open_refund"
    assert_includes codes, "refund_without_provider_confirmation"
    assert_includes codes, "refunded_license_policy_unresolved"
    assert_includes codes, "abandoned_provider_success_conflict"
    assert_equal before, database_snapshot
  end

  test "a confirmed refund whose license was actually canceled (via Commerce::ConfirmRefund) does not report refunded_license_policy_unresolved" do
    order = finalized_order
    refund = Commerce::RefundRequestSubmission.call!(user: order.user, order: order, reason_code: "other", customer_note: nil, at: @at)
    admin = User.create!(name: "관리자", email: "reconciliation-admin@example.com", password: "password123", role: :admin)
    Commerce::RefundRequestTransition.call!(refund_request: refund, actor: admin, action: "start_review", at: @at)
    Commerce::RefundRequestTransition.call!(refund_request: refund, actor: admin, action: "approve", at: @at)
    Commerce::RefundRequestTransition.call!(refund_request: refund, actor: admin, action: "mark_processing", at: @at)
    Commerce::ConfirmRefund.call!(refund_request: refund.reload, actor: admin, at: @at)

    report = Commerce::Reconciliation.call(stale_after: 30.minutes, at: @at, log: false)
    order_codes = report.issues.select { |issue| issue.order_public_id == order.public_id }.map(&:code)

    assert_not_includes order_codes, "refunded_license_policy_unresolved"
  end

  test "reconciliation reports duplicate open refund rows if database integrity is bypassed" do
    order = finalized_order
    duplicate_relation = Object.new
    duplicate_relation.define_singleton_method(:group) { |_column| self }
    duplicate_relation.define_singleton_method(:having) { |_condition| self }
    duplicate_relation.define_singleton_method(:count) { { order.id => 2 } }

    with_singleton_method(RefundRequest, :open, -> { duplicate_relation }) do
      report = Commerce::Reconciliation.call(at: @at, log: false)
      assert_includes report.issues.map(&:code), "duplicate_open_refund_requests"
    end
  end

  private

  def create_order(at: @at)
    @sequence += 1
    user = User.create!(
      name: "테스트 유저",
      email: "reconciliation-#{@sequence}@example.com",
      password: "password123",
      created_at: 30.days.ago
    )
    Commerce::OrderCreator.call!(
      user: user,
      product_code: "chatdox",
      offer_code: @offer.code,
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
      provider: order.provider,
      provider_payment_id: "reconciliation-payment-#{order.public_id}",
      order_id: order.public_id,
      amount: order.total_amount,
      currency: order.currency,
      provider_payload: { "status" => "DONE" }
    }
  end

  def create_overlapping_licenses
    user = User.create!(name: "테스트 유저", email: "overlap@example.com", password: "password123", created_at: 30.days.ago)
    first_start = @at.in_time_zone(KST).to_date
    [ first_start, first_start + 1.day ].each do |start_on|
      last_on = start_on + 1.month - 1.day
      License.create!(
        user: user,
        product: @product,
        source: "paid",
        status: "active",
        starts_on: start_on,
        last_usable_on: last_on,
        access_ends_at: KST.local((last_on + 1.day).year, (last_on + 1.day).month, (last_on + 1.day).day)
      )
    end
  end

  def create_refunded_request(order, confirmed:)
    request = Commerce::RefundRequestSubmission.call!(
      user: order.user,
      order: order,
      reason_code: "other",
      customer_note: nil,
      at: @at
    )
    request.update_columns(
      status: "refunded",
      provider_refund_status: confirmed ? "confirmed" : "pending",
      external_refund_confirmed: confirmed,
      external_processed_at: @at
    )
    request.reload
  end

  def database_snapshot
    [
      Order, OrderItem, PaymentTransaction, License, RefundRequest,
      CommerceAuditEvent, ExternalAccountLink
    ].to_h do |model|
      [ model.name, [ model.count, model.order(:id).pluck(:id, :updated_at) ] ]
    end
  end

  def with_singleton_method(object, method_name, replacement)
    original = object.method(method_name)
    object.define_singleton_method(method_name, replacement)
    yield
  ensure
    object.define_singleton_method(method_name, original)
  end
end
