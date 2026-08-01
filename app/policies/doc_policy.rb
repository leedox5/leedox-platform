class DocPolicy < ApplicationPolicy
  def chapter_number
    chapter_id = record.is_a?(Hash) ? record[:id] : record
    chapter_id.to_s.to_i
  end

  # Every call site (ProductContentController, ChapterProgressesController)
  # passes a chapter hash sourced from ProductContent -- chapters/find
  # always embed their own product_code, so there's no implicit-product
  # case left to fall back on. Fails loudly if that ever stops being true,
  # rather than silently assuming Chatdox.
  def product_code
    record.fetch(:product_code).to_s
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
    return season_access_decision.allowed? if season_aware_record?

    view_as_admin? || view_as_license? || view_as_trial? || view_as_guest?
  end

  def access_reason
    season_aware_record? ? season_access_decision.reason : (view? ? :allowed : :license_required)
  end

  private

  def content_source
    ProductContent.for(product_code)
  end

  def season_aware_record?
    record.is_a?(Hash) && record[:id].to_s.match?(/\AS\d{2}E\d{2}\z/)
  end

  def season_access_decision
    SeasonChapterAccessPolicy.new(user:, chapter: record, context: :direct).decision
  end
end
