require "securerandom"

module Commerce
  class OrderCreator
    class Unavailable < StandardError; end

    def self.call!(user:, product_code:, offer_code:, requested_start_on:, provider:, retry_of_order: nil, at: Time.current)
      new(
        user: user,
        product_code: product_code,
        offer_code: offer_code,
        requested_start_on: requested_start_on,
        provider: provider,
        retry_of_order: retry_of_order,
        at: at
      ).call!
    end

    def initialize(user:, product_code:, offer_code:, requested_start_on:, provider:, retry_of_order:, at:)
      @user = user
      @product_code = product_code
      @offer_code = offer_code
      @requested_start_on = requested_start_on.presence
      @provider = provider
      @retry_of_order = retry_of_order
      @at = at
    end

    def call!
      product = Product.find_by!(code: @product_code)
      raise Unavailable, "product is not for sale" unless Commerce::Sales.enabled_for?(product)

      offer = product.product_offers.find_by!(code: @offer_code)
      raise Unavailable, "offer is not available" unless offer.available_at?(@at)

      return create_lifetime_order!(product, offer) if offer.lifetime?

      requested_start_on = resolve_requested_start(product, offer)
      period = Commerce::LicenseScheduler.preview(
        user: @user,
        product: product,
        duration_months: offer.duration_months,
        requested_start_on: requested_start_on,
        at: @at
      )
      # KakaoPay only allows recurring/short-cycle billing for products where
      # payment-to-access-start stays within 12 months (handoff 0043) -- a
      # license already stacked far enough out (real repeat purchases, or
      # admin free grants like the ones that caused this) must block further
      # checkout stacking here rather than silently scheduling a start date
      # years away. Admin free grants (Commerce::GrantFreeLicense ->
      # LicenseScheduler.grant!) intentionally bypass OrderCreator entirely,
      # so this cap does not apply to them -- see result.md for why.
      if period.starts_on > max_license_start_on
        raise Unavailable, "license start date exceeds 12 months from purchase date"
      end

      ApplicationRecord.transaction do
        order = Order.create!(
          user: @user,
          public_id: SecureRandom.uuid,
          provider: @provider,
          status: "pending",
          requested_start_on: period.starts_on,
          supply_amount: offer.supply_amount,
          vat_amount: offer.vat_amount,
          total_amount: offer.total_amount,
          currency: offer.currency,
          payment_requested_at: @at,
          retry_of_order: @retry_of_order
        )
        order.order_items.create!(snapshot_attributes(product, offer))
        order.create_payment_transaction!(
          provider: @provider,
          provider_payment_id: "pending:#{order.public_id}",
          order_id: order.public_id,
          status: "pending",
          amount: order.total_amount,
          currency: order.currency,
          provider_payload: {}
        )
        order
      end
    end

    private

    # Handoff 0057 -- one-time Season purchase. No period to compute or stack:
    # the license starts today and never expires. One paid license per user and
    # Season; a refunded (canceled) one no longer counts, so it can be bought
    # again. Seasons that aren't published/listed can't be bought even if a
    # stale checkout link is still open.
    def create_lifetime_order!(product, offer)
      season = product.product_season
      raise Unavailable, "season is not on sale" unless season&.customer_reachable? && season.product_line.published?
      # A 0-won Season has no payment to make: it is started, not ordered
      # (a zero-amount order could never be confirmed by any payment provider).
      raise Unavailable, "free season cannot be ordered" if offer.total_amount.zero?
      raise Unavailable, "season is already purchased" if @user.licenses.where(product: product).not_canceled.exists?

      today = @at.in_time_zone(Commerce::PeriodCalculator::KST).to_date
      ApplicationRecord.transaction do
        order = Order.create!(
          user: @user, public_id: SecureRandom.uuid, provider: @provider, status: "pending",
          requested_start_on: today, supply_amount: offer.supply_amount, vat_amount: offer.vat_amount,
          total_amount: offer.total_amount, currency: offer.currency, payment_requested_at: @at,
          retry_of_order: @retry_of_order
        )
        order.order_items.create!(snapshot_attributes(product, offer))
        order.create_payment_transaction!(
          provider: @provider, provider_payment_id: "pending:#{order.public_id}", order_id: order.public_id,
          status: "pending", amount: order.total_amount, currency: order.currency, provider_payload: {}
        )
        order
      end
    end

    def max_license_start_on
      @at.in_time_zone(Commerce::PeriodCalculator::KST).to_date + 12.months
    end

    def resolve_requested_start(product, offer)
      existing_period = @user.licenses
        .where(product: product)
        .not_canceled
        .where("access_ends_at > ?", @at)
        .exists?

      return @at.in_time_zone(Commerce::PeriodCalculator::KST).to_date if existing_period

      date = @requested_start_on.present? ? Date.iso8601(@requested_start_on.to_s) : @at.in_time_zone(Commerce::PeriodCalculator::KST).to_date
      Commerce::PeriodCalculator.validate_start!(start_on: date, purchased_at: @at)
    rescue Date::Error
      raise ArgumentError, "start date is invalid"
    end

    def snapshot_attributes(product, offer)
      {
        product: product,
        product_offer: offer,
        product_code: product.code,
        product_name: product.name,
        offer_code: offer.code,
        offer_version: offer.version,
        duration_months: offer.duration_months,
        supply_amount: offer.supply_amount,
        vat_amount: offer.vat_amount,
        total_amount: offer.total_amount,
        discount_bps: offer.discount_bps,
        currency: offer.currency
      }
    end
  end
end
