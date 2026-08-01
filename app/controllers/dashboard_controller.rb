class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    authorize :dashboard, :access?

    @product_dashboards = Product.order(:code).map { |product| build_product_dashboard(product) }
    # The Trial banner promises access to chapters of products the user
    # hasn't bought yet -- once every product on sale is licensed, that
    # promise is moot even if the account-wide 7-day timer hasn't run out.
    @has_unowned_product = @product_dashboards.any? { |pd| !current_user.licensed_for?(pd[:product].code) }
  end

  private

  def build_product_dashboard(product)
    source = ProductContent.for(product.code)
    # A product's chapters may also include appendix chapters (kind:
    # :appendix) -- they're outside the story flow and explicitly excluded
    # from progress tracking, so they don't belong in this count.
    chapters = source.chapters.reject { |chapter| chapter[:kind] == :appendix }
    total = chapters.size

    summary = ProductContent::ProgressSummary.call(user: current_user, source:)

    completed_ids = current_user.chapter_progresses
      .where(product_code: product.code)
      .completed
      .order(completed_at: :desc)
      .pluck(:chapter_id)
    recent_chapters = completed_ids.filter_map do |id|
      identity = ProductContent::ChapterIdentity.normalize(product_code: product.code, chapter_id: id, source:)
      identity.aliases.filter_map { |candidate| source.find(candidate) }.first if identity.supported?
    end.uniq { |chapter| chapter[:id] }.first(3)

    {
      product: product,
      total: total,
      accessible: accessible_chapter_count(source, total),
      completed_count: summary.overall.completed_count,
      progress_percent: summary.overall.percentage,
      recent_chapters:,
      next_chapter: summary.overall.next_chapter
    }
  end

  # Equivalent to counting how many chapters 1..total pass
  # current_user.can_view_chapter?, but computed directly instead of
  # calling it in a loop -- access is monotonic in chapter number (whichever
  # tier applies unlocks a fixed prefix of chapters), and re-querying
  # licenses per chapter would mean up to `total` extra queries per product.
  def accessible_chapter_count(source, total)
    return total if current_user.admin? || current_user.licensed_for?(source.product_code)
    return [ total, source.trial_chapter_limit ].min if current_user.trial_active?

    [ total, source.guest_chapter_limit ].min
  end
end
