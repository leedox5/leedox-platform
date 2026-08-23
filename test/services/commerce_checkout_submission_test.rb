require "test_helper"

class CommerceCheckoutSubmissionTest < ActiveSupport::TestCase
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
    @buyer = User.create!(name: "테스트 유저", email: "checkout-dedup-buyer@example.com", password: "password123", created_at: 30.days.ago)
    @at = KST.local(2026, 7, 15, 12)
  end

  teardown do
    @previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "resubmitting the same offer reuses the existing pending order instead of creating a new one" do
    first = submit(offer_code: "chatdox-1m-v1")

    assert_no_difference "Order.count" do
      second = submit(offer_code: "chatdox-1m-v1")
      assert_equal first, second
    end
    assert_equal "pending", first.reload.status
  end

  test "switching to a different offer abandons the fresh evidence-free pending order and creates one new order" do
    first = submit(offer_code: "chatdox-1m-v1")

    assert_difference "Order.count", 1 do
      second = submit(offer_code: "chatdox-3m-v1")
      assert_not_equal first, second
      assert_equal "chatdox-3m-v1", second.order_items.first!.offer_code
    end

    assert_equal "abandoned", first.reload.status
    audit = first.commerce_audit_events.find_by!(action: "order_abandoned")
    assert_equal @buyer, audit.actor
    assert_equal %w[pending abandoned], [ audit.from_state, audit.to_state ]
  end

  test "switching offers on a pending order with provider evidence reuses it instead of abandoning" do
    first = submit(offer_code: "chatdox-1m-v1")
    first.payment_transaction.update!(provider_status: "PAID")

    assert_no_difference "Order.count" do
      second = submit(offer_code: "chatdox-3m-v1")
      assert_equal first, second
    end
    assert_equal "pending", first.reload.status
  end

  test "a stale evidence-free pending order under a different provider is abandoned, not silently reused (handoff: KakaoPay checkout choice)" do
    stale_manual = submit(offer_code: "chatdox-1m-v1", provider: "manual")

    assert_difference "Order.count", 1 do
      fresh_kakaopay = submit(offer_code: "chatdox-1m-v1", provider: "portone")
      assert_not_equal stale_manual, fresh_kakaopay
      assert_equal "portone", fresh_kakaopay.provider
    end

    assert_equal "abandoned", stale_manual.reload.status
  end

  test "a pending order under a different provider WITH evidence is left alone, not silently replaced" do
    in_flight_portone = submit(offer_code: "chatdox-1m-v1", provider: "portone")
    in_flight_portone.payment_transaction.update!(provider_status: "PAID")

    assert_no_difference "Order.count" do
      result = submit(offer_code: "chatdox-1m-v1", provider: "manual")
      assert_equal in_flight_portone, result
    end
    assert_equal "pending", in_flight_portone.reload.status
  end

  test "a paid order for the same product does not block or get touched by a fresh checkout submission" do
    paid = submit(offer_code: "chatdox-1m-v1")
    Commerce::OrderFinalizer.call!(
      order: paid,
      payment: {
        provider: "portone",
        provider_payment_id: "provider-payment-#{paid.public_id}",
        order_id: paid.public_id,
        amount: paid.total_amount,
        currency: paid.currency,
        provider_payload: { "status" => "PAID" }
      },
      at: @at
    )

    assert_difference "Order.count", 1 do
      renewal = submit(offer_code: "chatdox-1m-v1")
      assert_not_equal paid, renewal
      assert_equal "pending", renewal.status
    end
    assert_equal "paid", paid.reload.status
  end

  private

  def submit(offer_code:, at: @at, provider: "portone")
    Commerce::CheckoutSubmission.call!(
      user: @buyer,
      product_code: "chatdox",
      offer_code: offer_code,
      requested_start_on: at.in_time_zone(KST).to_date,
      provider: provider,
      at: at
    )
  end
end
