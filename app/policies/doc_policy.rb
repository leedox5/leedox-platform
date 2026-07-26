class DocPolicy < ApplicationPolicy
  def chapter_number
    chapter_id = record.is_a?(Hash) ? record[:id] : record
    chapter_id.to_s.to_i
  end

  def product_code
    return record[:product_code].to_s if record.is_a?(Hash) && record[:product_code].present?

    "chatdox"
  end

  def view_as_guest?
    chapter_number <= content_source.guest_chapter_limit
  end

  def view_as_trial?
    user&.trial_active? && chapter_number <= content_source.trial_chapter_limit
  end

  def view_as_license?
    Entitlements::ProductAccess.allowed?(
      user: user,
      product_code: product_code
    ) && content_source.licensed_chapter_ranges.any? { |range| range.cover?(chapter_number) }
  end

  def view_as_admin?
    user&.admin?
  end

  def view?
    view_as_admin? || view_as_license? || view_as_trial? || view_as_guest?
  end

  private

  def content_source
    ProductContent.for(product_code)
  end
end
