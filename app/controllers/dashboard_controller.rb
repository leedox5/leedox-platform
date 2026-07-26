class DashboardController < ApplicationController
  before_action :authenticate_user!

  # Chatdox has a hand-written chapter list (Curriculum); Claudox's chapter
  # list is derived by scanning markdown files (Claudox.all/.find). Both
  # expose the same shape (id/slug/title/...), so the rest of this controller
  # can treat every product's chapters uniformly through this lookup.
  CHAPTER_SOURCES = { "chatdox" => Curriculum, "claudox" => Claudox }.freeze

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
    source = CHAPTER_SOURCES[product.code]
    # Claudox.all also returns appendix chapters (kind: :appendix) -- they're
    # outside the 20-chapter story flow and explicitly excluded from progress
    # tracking, so they don't belong in this count. Curriculum's chapters have
    # no :kind key at all, so this reject is a no-op for Chatdox.
    chapters = (source ? source.all : []).reject { |chapter| chapter[:kind] == :appendix }
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
      accessible: accessible_chapter_count(product.code, total),
      completed_count: completed_count,
      progress_percent: progress_percent(completed_count, total),
      recent_chapters: source ? completed_ids.first(3).filter_map { |id| source.find(id) } : [],
      next_chapter: source ? chapters.find { |chapter| completed_ids.exclude?(chapter[:id]) } : nil
    }
  end

  # Equivalent to counting how many chapters 1..total pass
  # current_user.can_view_chapter?, but computed directly instead of
  # calling it in a loop -- access is monotonic in chapter number (whichever
  # tier applies unlocks a fixed prefix of chapters), and re-querying
  # licenses per chapter would mean up to `total` extra queries per product.
  def accessible_chapter_count(product_code, total)
    return total if current_user.admin? || current_user.licensed_for?(product_code)
    return [ total, 5 ].min if current_user.trial_active?

    [ total, 2 ].min
  end

  def progress_percent(completed_count, total_count)
    return 0 if total_count.zero?

    ((completed_count.to_f / total_count) * 100).round
  end
end
