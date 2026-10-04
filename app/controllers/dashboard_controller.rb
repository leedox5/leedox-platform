class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    authorize :dashboard, :access?

    # Handoff 0080 -- every license of the member, read once: the series in use and the expired
    # state of standalone products both come from it (no per-series or per-product license query).
    @user_licenses = current_user.licenses.includes(:product).to_a
    load_series_in_use

    all_dashboards = dashboard_products.map { |product| build_product_dashboard(product) }

    @owned_dashboards = all_dashboards.select { |pd| current_user.licensed_for?(pd[:product].code) }
    @unowned_dashboards = all_dashboards.reject { |pd| current_user.licensed_for?(pd[:product].code) }

    @product_dashboards = all_dashboards
    @has_unowned_product = @unowned_dashboards.any?
  end

  private

  # Handoff 0080 -- the series the member can use right now, newest license first. "In use" is
  # License#active_at? -- the check Entitlements::ProductAccess (the episode gate, ProductLine#
  # owned_by?) makes, and the same licenses /mypage labels 이용 중 (effective_status "active"); a
  # free start is such a license too. Only series a customer can open (ProductLine.customer_reachable,
  # the gate's own scope). A fixed number of queries whatever the number of series.
  def load_series_in_use
    active = @user_licenses.select(&:active_at?).group_by(&:product_id)
    lines = ProductLine.customer_reachable.where(product_id: active.keys)
      .includes(:product, cover_image_attachment: :blob).to_a
    @series_in_use = lines.sort_by { |line| [ -active[line.product_id].map(&:starts_on).max.jd, line.id ] }
    # The license whose period the card shows: an indefinite one if there is one, else the latest end.
    @series_licenses = lines.to_h do |line|
      [ line.id, License.longest_running(active[line.product_id]) ]
    end

    ids = lines.map(&:id)
    published = ContentEpisode.published.where(product_line_id: ids).ordered.to_a
    @series_published_counts = published.group_by(&:product_line_id).transform_values(&:size)
    @series_first_episodes = published.group_by(&:product_line_id).transform_values(&:first)
    # 공개 예정 = the 0070 judgment (ContentEpisode.upcoming), as on the home.
    @series_upcoming_counts = ContentEpisode.upcoming(ContentEpisode.where(product_line_id: ids))
      .group_by(&:product_line_id).transform_values(&:size)
  end

  # Handoff 0080 -- a standalone product the member has no usable license for, but whose latest
  # license simply ran out: what /mypage labels 만료 (License#effective_status "expired"). Canceled-only
  # or scheduled-only (not started yet) histories aren't "expired" there, so they stay 미보유 here.
  def expired_license_for(product)
    licenses = @user_licenses.select { |license| license.product_id == product.id }
    return nil if licenses.any?(&:active_at?)

    License.latest_expired(licenses)
  end

  def dashboard_products
    Product.standalone.active
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
      next_chapter: chapters.find { |chapter| completed_ids.exclude?(chapter[:id]) },
      expired_license: expired_license_for(product)
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
