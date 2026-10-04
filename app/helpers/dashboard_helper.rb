# Only the member dashboard uses these (the admin user list has its own Admin::UsersHelper). Handoff 0079:
# the card title already names the product, so the badge and period line no longer repeat it.
module DashboardHelper
  def product_status_badge(user, product)
    label, classes = if product.free_access?
      [ "무료로 이용 가능", "bg-emerald-100 text-emerald-700" ]
    elsif user.licensed_for?(product.code)
      [ "이용 중", "bg-emerald-100 text-emerald-700" ]
    else
      [ "미보유", "bg-gray-100 text-gray-700" ]
    end

    tag.span(label, class: "inline-flex rounded-full px-3 py-1 text-xs font-semibold #{classes}")
  end

  def product_period_text(user, product)
    if product.free_access?
      "라이선스 없이 전체 이용 가능합니다"
    elsif (license = user.licenses.for_product(product.code).not_canceled.find { |item| item.active_at? })
      license.indefinite? ? "무기한 이용 중" : "이용 종료일: #{I18n.l(license.last_usable_on, format: :long, locale: :ko)}"
    else
      "이용 중인 라이선스가 없습니다"
    end
  end
end
