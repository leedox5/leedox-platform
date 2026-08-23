module Payments
  class Configuration
    REQUIRED_KEYS = {
      "portone" => %w[PORTONE_API_SECRET PORTONE_STORE_ID PORTONE_CHANNEL_KEY PORTONE_WEBHOOK_SECRET]
    }.freeze
    WEBHOOK_KEYS = {
      "portone" => %w[PORTONE_API_SECRET PORTONE_WEBHOOK_SECRET]
    }.freeze

    attr_reader :provider

    def self.current
      new(provider: ENV["PAYMENT_PROVIDER"])
    end

    def initialize(provider:)
      @provider = provider.to_s
    end

    def ready?
      valid_provider? && missing_keys.empty?
    end

    def checkout_ready?
      provider == "portone" && ready?
    end

    # KakaoPay is currently the only PortOne payment method offered at
    # checkout (card is configured but not customer-facing for now -- see
    # PORTONE_CHANNEL_KEY/PORTONE_KAKAOPAY_CHANNEL_KEY, distinct PortOne
    # channels). Centralized here so BillingController (offering the choice)
    # and BillingOrdersController (deciding the order's actual provider) can't
    # drift out of sync on what "ready" means.
    def kakaopay_ready?
      checkout_ready? && ENV["PORTONE_KAKAOPAY_CHANNEL_KEY"].present?
    end

    def webhook_ready?
      valid_provider? && missing_webhook_keys.empty?
    end

    def valid_provider?
      Payments::Gateway::PROVIDERS.include?(provider)
    end

    def missing_keys
      return [ "PAYMENT_PROVIDER" ] unless valid_provider?

      REQUIRED_KEYS.fetch(provider).reject { |key| ENV[key].present? }
    end

    def missing_webhook_keys
      return [ "PAYMENT_PROVIDER" ] unless valid_provider?

      WEBHOOK_KEYS.fetch(provider).reject { |key| ENV[key].present? }
    end
  end
end
