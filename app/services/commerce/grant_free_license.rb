module Commerce
  # Zero-payment license issuance behind the /admin/users "1년 무료 부여" button
  # (handoff 0018) -- reuses LicenseScheduler/PeriodCalculator so a free grant
  # follows the exact same starts_on/access_ends_at math as a paid purchase,
  # just with source: "coupon" and no order_item. Records a CommerceAuditEvent
  # since this issues real license value without a payment behind it.
  class GrantFreeLicense
    DURATION_MONTHS = 12
    SOURCE = "coupon"

    def self.call!(user:, product:, actor:, at: Time.current)
      new(user: user, product: product, actor: actor, at: at).call!
    end

    def initialize(user:, product:, actor:, at:)
      @user = user
      @product = product
      @actor = actor
      @at = at
    end

    def call!
      raise Pundit::NotAuthorizedError unless @actor&.admin?

      # LicenseScheduler.grant! takes a row lock on @user internally
      # (@user.lock!), but that lock is only meaningful for the duration of an
      # enclosing transaction -- without one it releases right after the
      # SELECT, same as any bare `record.lock!` call. Wrapping here (matching
      # OrderFinalizer's pattern for the paid path) makes the lock actually
      # serialize concurrent grants for the same user, and keeps the license
      # and its audit event atomic -- no license ever persists without the
      # audit trail that makes a free, unpaid grant reviewable.
      ApplicationRecord.transaction do
        license = Commerce::LicenseScheduler.grant!(
          user: @user,
          product: @product,
          duration_months: DURATION_MONTHS,
          source: SOURCE,
          at: @at
        )

        Commerce::AuditRecorder.record!(
          actor: @actor,
          action: "free_license_granted",
          auditable: license,
          to_state: license.status,
          reason_code: "admin_free_grant",
          at: @at
        )

        license
      end
    end
  end
end
