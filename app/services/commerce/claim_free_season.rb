module Commerce
  # Explicit "무료 이용 시작" for a 0-won Season (handoff 0057): the user gets
  # an indefinite license with no order, payment transaction or payment
  # provider involved. Nothing is granted automatically -- the Season must have
  # its sale switched on by an admin, and the user must press the button.
  #
  # Duplicate protection: one non-canceled license per user and Season Product.
  # A second press (or a double click / two tabs) returns the existing license
  # unchanged; a concurrent race is caught by the unique
  # (user, product, starts_on) index and resolved to the same result.
  class ClaimFreeSeason
    class Unavailable < StandardError; end

    Result = Data.define(:license, :created)

    def self.call!(user:, season:, at: Time.current)
      new(user: user, season: season, at: at).call!
    end

    def initialize(user:, season:, at:)
      @user = user
      @season = season
      @at = at
    end

    def call!
      raise Unavailable, "free start is not available for this season" unless @season.free_start_open?

      product = @season.product
      ApplicationRecord.transaction do
        @user.lock!
        existing = @user.licenses.where(product: product).not_canceled.first
        return Result.new(license: existing, created: false) if existing

        license = License.create!(
          user: @user, product: product, order_item: nil, source: "free", status: "active",
          starts_on: @at.in_time_zone(Commerce::PeriodCalculator::KST).to_date,
          last_usable_on: nil, access_ends_at: nil
        )
        Commerce::AuditRecorder.record!(
          actor: @user, action: "season_free_access_claimed", auditable: license,
          to_state: license.status, reason_code: "free_season_claim", at: @at
        )
        Result.new(license: license, created: true)
      end
    rescue ActiveRecord::RecordNotUnique
      Result.new(license: @user.licenses.where(product: @season.product).not_canceled.first, created: false)
    end
  end
end
