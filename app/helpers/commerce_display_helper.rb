# Wording for term vs one-time (indefinite) purchases -- handoff 0057.
module CommerceDisplayHelper
  def duration_label(months)
    months.nil? ? "무기한" : "#{months}개월"
  end

  # "2026년 9월 21일 ~ 2027년 9월 20일" or "2026년 9월 21일 ~ 무기한"
  def license_span_text(license)
    starts = I18n.l(license.starts_on, locale: :ko, format: :long)
    ends = license.indefinite? ? "무기한" : I18n.l(license.last_usable_on, locale: :ko, format: :long)
    "#{starts} ~ #{ends}"
  end

  # Compact "2026-09-21~2027-09-20" / "2026-09-21~무기한" for admin tables.
  def license_span_compact(license)
    "#{license.starts_on}~#{license.indefinite? ? '무기한' : license.last_usable_on}"
  end
end
