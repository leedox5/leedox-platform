module Admin::UsersHelper
  # Admin-only period display -- deliberately separate from
  # DashboardHelper#product_period_text (customer-facing, long-form Korean
  # date), so changing this format never touches what customers see.
  def license_period_text(user, product)
    return "-" if product.free_access?

    period = contiguous_license_period(user, product)
    return "없음" unless period

    "#{period[:starts_on].strftime('%Y.%m.%d')} ~ #{period[:last_usable_on].strftime('%Y.%m.%d')}"
  end

  # Calculates contiguous active -> scheduled license chain starting from
  # active license (or earliest scheduled license if no active license).
  # Excludes canceled/expired licenses and does not bridge date gaps.
  def contiguous_license_period(user, product)
    licenses = user.licenses.for_product(product.code).not_canceled.to_a
    return nil if licenses.empty?

    active_license = licenses.find { |l| l.effective_status == "active" }
    scheduled_licenses = licenses.select { |l| l.effective_status == "scheduled" }

    anchor_license = active_license || scheduled_licenses.min_by(&:starts_on)
    return nil unless anchor_license

    start_date = anchor_license.starts_on
    current_end_date = anchor_license.last_usable_on

    loop do
      next_license = scheduled_licenses.find { |l| l.starts_on == current_end_date + 1.day }
      break unless next_license

      current_end_date = next_license.last_usable_on
    end

    { starts_on: start_date, last_usable_on: current_end_date, anchor: anchor_license }
  end

  def admin_product_status_badge(user, product)
    label, classes = if product.free_access?
      [ "#{product.name} 무료로 이용 가능", "bg-emerald-100 text-emerald-700" ]
    elsif user.licensed_for?(product.code)
      [ "#{product.name} 이용 중", "bg-emerald-100 text-emerald-700" ]
    elsif user.licenses.for_product(product.code).not_canceled.any? { |l| l.effective_status == "scheduled" }
      [ "#{product.name} 이용 예정", "bg-blue-100 text-blue-700" ]
    else
      [ "#{product.name} 미보유", "bg-gray-100 text-gray-700" ]
    end

    tag.span(label, class: "inline-flex rounded-full px-3 py-1 text-xs font-semibold #{classes}")
  end

  def user_owned_products(user, products)
    products.select do |product|
      user.licensed_for?(product.code) ||
        user.licenses.for_product(product.code).not_canceled.any? { |l| l.effective_status == "scheduled" }
    end
  end

  # "미보유: Chatdox, Antigravity" summary line for the 구독 column (handoff
  # 0018) -- products the user doesn't currently hold get folded into one
  # line instead of a badge+period block each, so the column stays ~2 lines
  # for the common case instead of growing with every product added.
  def unowned_products_line(user, products)
    owned = user_owned_products(user, products)
    names = products.reject { |product| owned.include?(product) }.map(&:name)
    return if names.empty?

    "미보유: #{names.join(', ')}"
  end

  # A not-yet-expired license (active or scheduled) for the same product --
  # used to warn before a free grant would stack on top of one the user
  # already has, rather than silently piling licenses up on a double-click.
  def active_or_scheduled_license(user, product)
    user.licenses.for_product(product.code).not_canceled.find { |license| license.effective_status != "expired" }
  end

  def preview_free_license_grant(user, product)
    Commerce::LicenseScheduler.preview(
      user: user,
      product: product,
      duration_months: Commerce::GrantFreeLicense::DURATION_MONTHS,
      requested_start_on: Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    )
  end

  # Free grants go through the same LicenseScheduler stacking math as a paid
  # order, but skip OrderCreator's own 12-month-out cap entirely (that check
  # lives in OrderCreator#max_license_start_on, not LicenseScheduler, and a
  # free grant never touches OrderCreator) -- so unlike checkout, nothing
  # here blocks it. That's intentional (handoff 0050): a free grant is a
  # deliberate admin action, not a shopper checking out, so the admin gets a
  # warning instead of a hard stop and decides for themselves.
  def free_grant_exceeds_twelve_months?(preview, at: Time.current)
    preview.starts_on > (at.in_time_zone(Commerce::PeriodCalculator::KST).to_date + 12.months)
  end

  # data-turbo-confirm only renders a native confirm() -- there's no HTML
  # behind it to style, so the "current expiry / new expiry" facts the admin
  # needs before clicking have to fit in this plain-text message (handoff
  # 0050). Identifies the target by email, not just name, since admin/test
  # accounts routinely share the same display name (see this file's own
  # fixtures) and email is what's actually unique.
  def grant_free_license_confirm_message(user, product)
    current_period = contiguous_license_period(user, product)
    preview = preview_free_license_grant(user, product)
    new_period_str = "#{preview.starts_on.strftime('%Y.%m.%d')} ~ #{preview.last_usable_on.strftime('%Y.%m.%d')}"
    final_end_str = preview.last_usable_on.strftime("%Y.%m.%d")

    message = if current_period
      current_end_str = current_period[:last_usable_on].strftime("%Y.%m.%d")
      "#{user.name}(#{user.email})님은 이미 #{product.name} 라이선스가 있습니다 (현재 종료일: #{current_end_str}). 1년을 추가로 부여하시겠습니까?\n(추가 기간: #{new_period_str}, 최종 종료일: #{final_end_str})"
    else
      "#{user.name}(#{user.email})님에게 #{product.name} 1년 무료 라이선스를 부여하시겠습니까? (현재 라이선스 없음 → 이용 기간: #{new_period_str})"
    end

    if free_grant_exceeds_twelve_months?(preview)
      message += "\n\n⚠ 이 부여로 만료일이 오늘부터 12개월을 넘어섭니다 (최종 종료일: #{final_end_str})."
    end

    message
  end
end
