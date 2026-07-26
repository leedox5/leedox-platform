module DashboardHelper
  # Per-product versions used by the dashboard (R2) -- subscription_badge/
  # subscription_period_text below stay Chatdox-only because they're still
  # used by admin/users/index.html.erb's compact user list, which is out of
  # scope for this round.
  def product_status_badge(user, product)
    label, classes = if user.licensed_for?(product.code)
      [ "#{product.name} 이용 중", "bg-emerald-100 text-emerald-700" ]
    else
      [ "#{product.name} 미보유", "bg-gray-100 text-gray-700" ]
    end

    tag.span(label, class: "inline-flex rounded-full px-3 py-1 text-xs font-semibold #{classes}")
  end

  def product_period_text(user, product)
    if (license = user.licenses.for_product(product.code).not_canceled.find { |item| item.active_at? })
      "#{product.name} 이용 종료일: #{I18n.l(license.last_usable_on, format: :long, locale: :ko)}"
    else
      "#{product.name} 이용 중인 라이선스가 없습니다"
    end
  end

  def subscription_badge(user)
    label, classes = if user.licensed_for?("chatdox")
      [ "Chatdox 이용 중", "bg-emerald-100 text-emerald-700" ]
    elsif user.trial_active?
      [ "무료 Trial", "bg-violet-100 text-violet-700" ]
    else
      [ "이용 불가", "bg-gray-100 text-gray-700" ]
    end

    tag.span(label, class: "inline-flex rounded-full px-3 py-1 text-sm font-semibold #{classes}")
  end

  def subscription_period_text(user)
    if (license = user.licenses.for_product("chatdox").not_canceled.find { |item| item.active_at? })
      "Chatdox 이용 종료일: #{I18n.l(license.last_usable_on, format: :long, locale: :ko)}"
    elsif user.trial_active?
      "무료 Trial #{user.trial_days_remaining}일 남음"
    else
      "이용 가능한 라이선스가 없습니다"
    end
  end
end
