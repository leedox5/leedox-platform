require "test_helper"

class PaymentsConfigurationTest < ActiveSupport::TestCase
  KEYS = %w[
    PAYMENT_PROVIDER
    PORTONE_API_SECRET PORTONE_STORE_ID PORTONE_CHANNEL_KEY PORTONE_KAKAOPAY_CHANNEL_KEY PORTONE_WEBHOOK_SECRET
  ].freeze

  setup do
    @previous = KEYS.to_h { |key| [ key, ENV[key] ] }
    KEYS.each { |key| ENV.delete(key) }
  end

  teardown do
    @previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "PortOne configuration reports names only and requires every sale setting" do
    portone = Payments::Configuration.new(provider: "portone")
    assert_not portone.ready?
    assert_equal %w[PORTONE_API_SECRET PORTONE_STORE_ID PORTONE_CHANNEL_KEY PORTONE_WEBHOOK_SECRET], portone.missing_keys

    ENV["PORTONE_API_SECRET"] = "test-api"
    ENV["PORTONE_STORE_ID"] = "test-store"
    ENV["PORTONE_CHANNEL_KEY"] = "test-channel"
    ENV["PORTONE_WEBHOOK_SECRET"] = "test-webhook"
    assert portone.ready?
    assert portone.checkout_ready?
    assert portone.webhook_ready?
  end

  test "kakaopay_ready? requires checkout_ready? plus its own channel key" do
    portone = Payments::Configuration.new(provider: "portone")
    assert_not portone.kakaopay_ready?

    ENV["PORTONE_API_SECRET"] = "test-api"
    ENV["PORTONE_STORE_ID"] = "test-store"
    ENV["PORTONE_CHANNEL_KEY"] = "test-channel"
    ENV["PORTONE_WEBHOOK_SECRET"] = "test-webhook"
    assert portone.checkout_ready?
    assert_not portone.kakaopay_ready?, "checkout_ready? alone must not be enough -- KakaoPay needs its own channel key"

    ENV["PORTONE_KAKAOPAY_CHANNEL_KEY"] = "test-kakaopay-channel"
    assert portone.kakaopay_ready?
  end

  test "invalid provider fails closed" do
    configuration = Payments::Configuration.new(provider: "unconfigured")

    assert_not configuration.ready?
    assert_not configuration.webhook_ready?
    assert_equal [ "PAYMENT_PROVIDER" ], configuration.missing_keys
  end

  test "current configuration and gateway require an explicit exact provider" do
    [ nil, "", " ", "PortOne", "unknown", "toss" ].each do |value|
      value.nil? ? ENV.delete("PAYMENT_PROVIDER") : ENV["PAYMENT_PROVIDER"] = value

      assert_not Payments::Configuration.current.valid_provider?
      assert_raises(KeyError) { Payments::Gateway.current }
    end

    ENV["PAYMENT_PROVIDER"] = "portone"
    assert_equal "portone", Payments::Configuration.current.provider
    assert_instance_of Payments::PortoneGateway, Payments::Gateway.current
  end
end
