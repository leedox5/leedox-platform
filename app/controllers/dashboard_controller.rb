class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    authorize :dashboard, :access?

    all_dashboards = dashboard_products.map { |product| build_product_dashboard(product) }

    @owned_dashboards = all_dashboards.select { |pd| current_user.licensed_for?(pd[:product].code) }
    @unowned_dashboards = all_dashboards.reject { |pd| current_user.licensed_for?(pd[:product].code) }

    @product_dashboards = all_dashboards
    @has_unowned_product = @unowned_dashboards.any?
  end

  private

  def dashboard_products
    Product.active
      .where(free_access: false)
      .joins(:product_offers)
      .merge(ProductOffer.active)
      .distinct
      .to_a
      .sort_by { |product| [ current_user.licensed_for?(product.code) ? 0 : 1, product.code ] }
  end

  def build_product_dashboard(product)
    source = ProductContent.for(product.code)
    # A product's chapters may also include appendix chapters (kind:
    # :appendix) -- they're outside the story flow and explicitly excluded
    # from progress tracking, so they don't belong in this count.
    chapters = source.chapters.reject { |chapter| chapter[:kind] == :appendix }
    total = chapters.size

    completed_ids = current_user.chapter_progresses
      .where(product_code: product.code)
      .completed
      .order(completed_at: :desc)
      .pluck(:chapter_id)
    completed_count = completed_ids.size

    {
      product: product,
      total: total,
      accessible: accessible_chapter_count(source, total),
      # What this same product drops back to once trial ends (handoff 0046) --
      # always computed, regardless of the viewer's current state, so the view
      # can decide when it's actually worth showing (trial-active, unlicensed,
      # and only when it differs from `accessible`). Per-product because
      # guest/trial limits are set per product, not globally.
      accessible_after_trial: [ total, source.guest_chapter_limit ].min,
      completed_count: completed_count,
      progress_percent: progress_percent(completed_count, total),
      recent_chapters: completed_ids.first(3).filter_map { |id| source.find(id) },
      next_chapter: chapters.find { |chapter| completed_ids.exclude?(chapter[:id]) }
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

  def progress_percent(completed_count, total_count)
    return 0 if total_count.zero?

    ((completed_count.to_f / total_count) * 100).round
  end
end
