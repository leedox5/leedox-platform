# Only the member dashboard uses these (the admin user list has its own Admin::UsersHelper). Handoff 0079:
# the card title already names the product, so the badge and period line no longer repeat it.
# Handoff 0080: a standalone product whose license simply ran out reads 만료 (what /mypage says), and a
# series card's period line uses the same wording as a product's (dashboard_license_period_text).
# Handoff 0085: the dashboard shows an earlier product only while it's in use, so the 만료 branches went with its
# 더 둘러보기 cards (license_expired_period_text stays -- /mypage uses it).
# Handoff 0089: every card on the dashboard is something in use, so the old per-state badge (product_status_badge)
# and period text (product_period_text) became the one 이용 중 badge below; the period line is dashboard_license_period_text.
module DashboardHelper
  # Handoff 0084 (D-010) colors, in a .rb file so Tailwind extracts them (0084's lesson). [label, classes] -- the
  # shape product_lines/_list_card's `badge:` takes; the earlier-product card uses the same pair.
  DASHBOARD_IN_USE_BADGE = [
    "이용 중",
    "flex-shrink-0 whitespace-nowrap rounded-full border border-ok-soft/40 bg-ok-soft/10 px-3 py-1 text-xs font-bold text-ok-ink"
  ].freeze

  def dashboard_in_use_badge = DASHBOARD_IN_USE_BADGE

  # The period line of a usable license -- one wording for a product card and a series card. Prefixed
  # because every helper is mixed into every view and Admin::UsersHelper already has a
  # license_period_text(user, product) of its own.
  def dashboard_license_period_text(license)
    license.indefinite? ? "무기한 이용 중" : "이용 종료일: #{I18n.l(license.last_usable_on, format: :long, locale: :ko)}"
  end

  # Handoff 0080/0081 -- an ended license (/mypage 만료 cards; the dashboard's went in 0085).
  def license_expired_period_text(license)
    "이용 기간이 끝났습니다 (#{I18n.l(license.last_usable_on, format: :long, locale: :ko)}까지)"
  end

  # Handoff 0081 -- a license that hasn't started yet (/mypage 이용 예정 cards).
  def license_scheduled_period_text(license)
    "#{I18n.l(license.starts_on, format: :long, locale: :ko)}부터 이용 예정"
  end
end
