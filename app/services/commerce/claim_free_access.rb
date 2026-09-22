module Commerce
  # Explicit "무료 이용 시작" for a 0-won product line (handoff 0057, moved from
  # Season to ProductLine in 0065): the user gets an indefinite license with no
  # order, payment transaction or payment provider involved. Nothing is granted
  # automatically -- the product must have its sale switched on by an admin, and
  # the user must press the button.
  #
  # Duplicate protection: one non-canceled license per user and product.
  # A second press (or a double click / two tabs) returns the existing license
  # unchanged; a concurrent race is caught by the unique
  # (user, product, starts_on) index and resolved to the same result.
  class ClaimFreeAccess
    class Unavailable < StandardError; end

    Result = Data.define(:license, :created)

    def self.call!(user:, product_line:, at: Time.current)
      new(user: user, product_line: product_line, at: at).call!
    end

    def initialize(user:, product_line:, at:)
      @user = user
      @line = product_line
      @at = at
    end

    def call!
      raise Unavailable, "free start is not available for this product" unless @line.free_start_open?

      product = @line.product
      ApplicationRecord.transaction do
        @user.lock!
        existing = @user.licenses.where(product: product).not_canceled.first
        return Result.new(license: existing, created: false) if existing

        license = License.create!(
          user: @user, product: product, order_item: nil, source: "free", status: "active",
          starts_on: @at.in_time_zone(Commerce::PeriodCalculator::KST).to_date,
          last_usable_on: nil, access_ends_at: nil
        )
        # The action / reason strings keep their pre-0065 "season" wording: events
        # already recorded use them, and reports read them as one series.
        Commerce::AuditRecorder.record!(
          actor: @user, action: "season_free_access_claimed", auditable: license,
          to_state: license.status, reason_code: "free_season_claim", at: @at
        )
        Result.new(license: license, created: true)
      end
    rescue ActiveRecord::RecordNotUnique
      Result.new(license: @user.licenses.where(product: @line.product).not_canceled.first, created: false)
    end
  end
end
