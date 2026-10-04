class DashboardController < ApplicationController
  BROWSE_LIMIT = 4

  before_action :authenticate_user!

  def show
    authorize :dashboard, :access?

    # Handoff 0080 -- every license of the member, read once: the series in use and (0085) the earlier
    # products in use both come from it (no per-series or per-product license query).
    @user_licenses = current_user.licenses.includes(:product).to_a
    load_series_in_use

    # Handoff 0085 R1 -- the dashboard answers "what can I watch": earlier products only while a paid license is
    # usable now, and the series not in use (not earlier products) under 더 둘러보기.
    @owned_dashboards = legacy_products_in_use.map { |product| build_product_dashboard(product) }
    load_series_to_browse
    # Handoff 0086 -- no trial banners (D-N / ended) any more; the trial itself (more chapters of the earlier
    # products early on, accessible_chapter_count / DocPolicy) is unchanged.
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

  # Handoff 0085 R1 -- an earlier (standalone, paid) product the member holds a license usable right now
  # (License#active_at?, the check Entitlements::ProductAccess and the chapter gate make; scheduled-only or ended
  # licenses don't count). It no longer depends on the product being on sale: with sale_enabled off or every offer
  # off the license still opens the chapters (DocPolicy#view_as_license?). It does need the product active --
  # ProductContentController#enforce_active_product 404s an inactive product's chapters even for a license holder,
  # so a card there would lead nowhere.
  def legacy_products_in_use
    product_ids = @user_licenses.select(&:active_at?).map(&:product_id).uniq
    Product.standalone.active.where(free_access: false, id: product_ids).order(:code).to_a
  end

  # Handoff 0085 R1 -- 더 둘러보기: the series on /products (ProductLine.listed, the same order) the member isn't
  # using (not in @series_in_use), at most BROWSE_LIMIT. Not in use means no usable license, so the list badge's
  # state is computed with owned: false -- the same ProductLine#access_state /products uses.
  def load_series_to_browse
    lines = ProductLine.listed.where.not(id: @series_in_use.map(&:id)).order(:id).limit(BROWSE_LIMIT)
      .includes(:product, cover_image_attachment: :blob).to_a
    @browse_series = lines
    @browse_states = lines.to_h { |line| [ line.id, line.access_state(owned: false) ] }
    @browse_published_counts = ContentEpisode.where(product_line_id: lines.map(&:id), status: "published")
      .group(:product_line_id).count
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
