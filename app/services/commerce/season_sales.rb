module Commerce
  # Admin operations behind the Season "판매 설정" panel (handoff 0057):
  # one one-time price per ProductSeason, and an explicit sale on/off switch.
  #
  #  - A Season only gets a commerce Product when its price is first set, so
  #    Seasons that are never priced stay free and unaffected.
  #  - The price is a ProductOffer with no duration (a one-time purchase whose
  #    license never expires -- see License#indefinite?). It is entered VAT
  #    included and split 10% VAT like the existing offers. 0 is allowed: a
  #    0-won Season is free -- no order or payment, see Commerce::ClaimFreeSeason.
  #  - Sales start stopped. Starting one is an explicit action; stopping only
  #    blocks new purchases -- licenses already issued are never touched.
  #  - Changing the price between paid and free (0) stops the sale, so it must
  #    be started again on purpose. Any other price change leaves it as it was.
  #  - Changing the price edits the offer in place; existing orders keep their
  #    own amount snapshot (OrderItem/Order), so past purchases are unchanged.
  class SeasonSales
    class Invalid < StandardError; end

    VAT_DIVISOR = 1.1
    OFFER_VERSION = 1

    def self.set_price!(season:, total_amount:, actor:, at: Time.current)
      new(season: season, actor: actor, at: at).set_price!(total_amount)
    end

    def self.start_sale!(season:, actor:, at: Time.current)
      new(season: season, actor: actor, at: at).start_sale!
    end

    def self.stop_sale!(season:, actor:, at: Time.current)
      new(season: season, actor: actor, at: at).stop_sale!
    end

    def initialize(season:, actor:, at:)
      @season = season
      @actor = actor
      @at = at
    end

    def set_price!(total_amount)
      require_admin!
      total = parse_amount(total_amount)

      ApplicationRecord.transaction do
        @season.lock!
        product = @season.product || create_product!
        offer = product.product_offers.lifetime.find_or_initialize_by(version: OFFER_VERSION)
        previous_total = offer.total_amount

        supply = (total / VAT_DIVISOR).round
        offer.assign_attributes(
          code: offer.code.presence || "#{product.code}-once-v#{OFFER_VERSION}",
          duration_months: nil, currency: "KRW", active: true, discount_bps: 0,
          supply_amount: supply, vat_amount: total - supply, total_amount: total
        )
        offer.save!

        Commerce::AuditRecorder.record!(
          actor: @actor, action: "product_pricing_updated", auditable: product,
          from_state: previous_total&.to_s, to_state: total.to_s, reason_code: "season_price_set", at: @at
        )
        # Crossing between paid and free (0) changes what a visitor gets without
        # paying, so a typo can't silently give a Season away (or start charging
        # for one): the sale is stopped and must be started again explicitly.
        toggle!(product, false) if product.sale_enabled? && previous_total && previous_total.zero? != total.zero?
        offer
      end
    end

    def start_sale!
      require_admin!

      ApplicationRecord.transaction do
        @season.lock!
        product = @season.product
        raise Invalid, "가격을 먼저 저장해야 판매를 시작할 수 있습니다." unless product && @season.lifetime_offer
        unless @season.product_line.published? && @season.customer_reachable?
          raise Invalid, "제품과 Season이 공개(published)이고 비공개(private)가 아니어야 판매를 시작할 수 있습니다."
        end

        toggle!(product, true)
      end
    end

    def stop_sale!
      require_admin!

      ApplicationRecord.transaction do
        @season.lock!
        product = @season.product
        raise Invalid, "판매 설정이 없는 Season입니다." unless product

        toggle!(product, false)
      end
    end

    private

    def toggle!(product, enabled)
      previous = product.sale_enabled?
      product.update!(sale_enabled: enabled)
      Commerce::AuditRecorder.record!(
        actor: @actor, action: "product_sale_toggled", auditable: product,
        from_state: previous.to_s, to_state: enabled.to_s, reason_code: "season_sale_toggled", at: @at
      )
      product
    end

    def require_admin!
      raise Pundit::NotAuthorizedError unless @actor&.admin?
    end

    def parse_amount(value)
      total = Integer(value.to_s.delete(",").strip, exception: false)
      raise Invalid, "가격은 0원 이상의 정수여야 합니다. (0원이면 무료 Season입니다.)" unless total && total >= 0

      total
    end

    # Season slugs are kebab-case, Product codes are snake_case starting with a
    # letter; collisions with existing Products get a numeric suffix.
    def create_product!
      base = "#{@season.product_line.slug}_#{@season.slug}".tr("-", "_")
      base = "p_#{base}" unless base.match?(/\A[a-z]/)
      code = base
      suffix = 1
      code = "#{base}_#{suffix += 1}" while Product.exists?(code: code)

      product = Product.create!(
        code: code,
        name: "#{@season.product_line.customer_name} #{@season.season_code}",
        active: true,
        sale_enabled: false,
        landing_page_path: "/products/#{@season.product_line.slug}/#{@season.slug}"
      )
      @season.update!(product: product)
      product
    end
  end
end
