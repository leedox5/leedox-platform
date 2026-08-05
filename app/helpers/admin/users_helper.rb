module Admin::UsersHelper
  # Admin-only period display -- deliberately separate from
  # DashboardHelper#product_period_text (customer-facing, long-form Korean
  # date), so changing this format never touches what customers see.
  def license_period_text(user, product)
    return "-" if product.free_access?

    license = user.licenses.for_product(product.code).not_canceled.find { |item| item.active_at? }
    return "없음" unless license

    "#{license.starts_on.strftime('%Y.%m.%d')} ~ #{license.last_usable_on.strftime('%Y.%m.%d')}"
  end

  # "미보유: Chatdox, Antigravity" summary line for the 구독 column (handoff
  # 0018) -- products the user doesn't currently hold get folded into one
  # line instead of a badge+period block each, so the column stays ~2 lines
  # for the common case instead of growing with every product added.
  def unowned_products_line(user, products)
    names = products.reject { |product| user.licensed_for?(product.code) }.map(&:name)
    return if names.empty?

    "미보유: #{names.join(', ')}"
  end

  # A not-yet-expired license (active or scheduled) for the same product --
  # used to warn before a free grant would stack on top of one the user
  # already has, rather than silently piling licenses up on a double-click.
  def active_or_scheduled_license(user, product)
    user.licenses.for_product(product.code).not_canceled.find { |license| license.effective_status != "expired" }
  end

  def grant_free_license_confirm_message(user, product)
    existing = active_or_scheduled_license(user, product)
    return "#{user.name}님에게 #{product.name} 1년 무료 라이선스를 부여하시겠습니까?" unless existing

    period = "#{existing.starts_on.strftime('%Y.%m.%d')}~#{existing.last_usable_on.strftime('%Y.%m.%d')}"
    "#{user.name}님은 이미 #{product.name} 라이선스가 있습니다(#{period}). 그래도 1년을 추가로 부여하시겠습니까?"
  end
end
