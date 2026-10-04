# Only the member dashboard uses these (the admin user list has its own Admin::UsersHelper). Handoff 0079:
# the card title already names the product, so the badge and period line no longer repeat it.
# Handoff 0080: a standalone product whose license simply ran out reads 만료 (what /mypage says), and a
# series card's period line uses the same wording as a product's (dashboard_license_period_text).
module DashboardHelper
  def product_status_badge(user, product, expired_license: nil)
    # Handoff 0084 (D-010) -- the dashboard is dark; the badges keep their meaning colors (in use/free green,
    # expired amber, not owned grey) in the dark palette.
    label, classes = if product.free_access?
      [ "무료로 이용 가능", "border-[#7dd3a8]/40 bg-[#7dd3a8]/10 text-[#7dd3a8]" ]
    elsif user.licensed_for?(product.code)
      [ "이용 중", "border-[#7dd3a8]/40 bg-[#7dd3a8]/10 text-[#7dd3a8]" ]
    elsif expired_license
      [ "만료", "border-[#f0a53c]/40 bg-[#f0a53c]/10 text-[#f0a53c]" ]
    else
      [ "미보유", "border-white/15 bg-white/5 text-[#a8a39a]" ]
    end

    tag.span(label, class: "inline-flex shrink-0 whitespace-nowrap rounded-full border px-3 py-1 text-xs font-semibold #{classes}")
  end

  def product_period_text(user, product, expired_license: nil)
    if product.free_access?
      "라이선스 없이 전체 이용 가능합니다"
    elsif (license = user.licenses.for_product(product.code).not_canceled.find { |item| item.active_at? })
      dashboard_license_period_text(license)
    elsif expired_license
      license_expired_period_text(expired_license)
    else
      "이용 중인 라이선스가 없습니다"
    end
  end

  # The period line of a usable license -- one wording for a product card and a series card. Prefixed
  # because every helper is mixed into every view and Admin::UsersHelper already has a
  # license_period_text(user, product) of its own.
  def dashboard_license_period_text(license)
    license.indefinite? ? "무기한 이용 중" : "이용 종료일: #{I18n.l(license.last_usable_on, format: :long, locale: :ko)}"
  end

  # Handoff 0080/0081 -- an ended license (dashboard 만료 cards, /mypage 만료 cards).
  def license_expired_period_text(license)
    "이용 기간이 끝났습니다 (#{I18n.l(license.last_usable_on, format: :long, locale: :ko)}까지)"
  end

  # Handoff 0081 -- a license that hasn't started yet (/mypage 이용 예정 cards).
  def license_scheduled_period_text(license)
    "#{I18n.l(license.starts_on, format: :long, locale: :ko)}부터 이용 예정"
  end
end
