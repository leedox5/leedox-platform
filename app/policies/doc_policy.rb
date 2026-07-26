class DocPolicy < ApplicationPolicy
  # Ranges a paid license unlocks. 90..99 is Claudox's appendix range --
  # harmless for Chatdox since DocsController#show only ever resolves chapter
  # ids "01".."20" via Curriculum.find, so this policy is never even reached
  # for a Chatdox chapter number outside that range.
  LICENSED_CHAPTER_RANGES = [ 1..20, 90..99 ].freeze

  def chapter_number
    chapter_id = record.is_a?(Hash) ? record[:id] : record
    chapter_id.to_s.to_i
  end

  def product_code
    return record[:product_code].to_s if record.is_a?(Hash) && record[:product_code].present?

    "chatdox"
  end

  def view_as_guest?
    chapter_number <= 2
  end

  def view_as_trial?
    user&.trial_active? && chapter_number <= 5
  end

  def view_as_license?
    Entitlements::ProductAccess.allowed?(
      user: user,
      product_code: product_code
    ) && LICENSED_CHAPTER_RANGES.any? { |range| range.cover?(chapter_number) }
  end

  def view_as_admin?
    user&.admin?
  end

  def view?
    view_as_admin? || view_as_license? || view_as_trial? || view_as_guest?
  end
end
