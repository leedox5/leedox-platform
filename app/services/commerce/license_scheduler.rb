module Commerce
  class LicenseScheduler
    def self.preview(user:, product:, duration_months:, requested_start_on:, at: Time.current)
      new(
        user: user,
        product: product,
        duration_months: duration_months,
        requested_start_on: requested_start_on,
        at: at
      ).preview
    end

    def self.create_for!(user:, order_item:, requested_start_on:, at: Time.current)
      new(
        user: user,
        product: order_item.product,
        duration_months: order_item.duration_months,
        requested_start_on: requested_start_on,
        at: at
      ).create_for!(order_item)
    end

    # No order_item -- for admin-issued free grants (handoff 0018) that never
    # went through checkout. Reuses the same starts_on/access_ends_at math and
    # the same next_start_on staggering (so a grant on top of an existing
    # license extends it rather than overlapping), just with a caller-chosen
    # source instead of "paid".
    def self.grant!(user:, product:, duration_months:, source:, at: Time.current)
      requested_start_on = at.in_time_zone(Commerce::PeriodCalculator::KST).to_date
      new(
        user: user,
        product: product,
        duration_months: duration_months,
        requested_start_on: requested_start_on,
        at: at
      ).create_for!(nil, source: source)
    end

    def initialize(user:, product:, duration_months:, requested_start_on:, at:)
      @user = user
      @product = product
      @duration_months = duration_months
      @requested_start_on = requested_start_on.to_date
      @at = at
    end

    def preview
      Commerce::PeriodCalculator.call(
        start_on: next_start_on,
        duration_months: @duration_months
      )
    end

    def create_for!(order_item, source: "paid")
      @user.lock!
      period = preview
      status = period.starts_on > @at.in_time_zone(Commerce::PeriodCalculator::KST).to_date ? "scheduled" : "active"

      License.create!(
        user: @user,
        product: @product,
        order_item: order_item,
        source: source,
        status: status,
        starts_on: period.starts_on,
        last_usable_on: period.last_usable_on,
        access_ends_at: period.access_ends_at
      )
    end

    private

    def next_start_on
      latest = @user.licenses
        .where(product: @product)
        .not_canceled
        .where("access_ends_at > ?", @at)
        .maximum(:last_usable_on)

      latest ? latest + 1.day : @requested_start_on
    end
  end
end
