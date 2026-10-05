class DashboardController < ApplicationController
  BROWSE_LIMIT = 4

  before_action :authenticate_user!

  def show
    authorize :dashboard, :access?

    # Handoff 0080 -- every license of the member, read once: the series in use and (0085) the earlier
    # products in use both come from it (no per-series or per-product license query).
    @user_licenses = current_user.licenses.includes(:product).to_a
    @active_licenses = @user_licenses.select(&:active_at?).group_by(&:product_id)
    load_series_in_use

    # Handoff 0085 R1 -- the dashboard answers "what can I watch": earlier products only while a paid license is
    # usable now, and the series not in use (not earlier products) under 다른 콘텐츠 (0089; was 더 둘러보기).
    # Handoff 0089 -- a simple card per product (name, 이용 중, period); no chapter counts or reading progress.
    @legacy_products = legacy_products_in_use
    @legacy_licenses = @legacy_products.to_h { |product| [ product.id, License.longest_running(@active_licenses[product.id]) ] }
    load_series_to_browse
    # Handoff 0086 -- no trial banners (D-N / ended) any more; the trial itself (more chapters of the earlier
    # products early on, DocPolicy#view_as_trial?) is unchanged.
  end

  private

  # Handoff 0080 -- the series the member can use right now, newest license first. "In use" is
  # License#active_at? -- the check Entitlements::ProductAccess (the episode gate, ProductLine#
  # owned_by?) makes, and the same licenses /mypage labels 이용 중 (effective_status "active"); a
  # free start is such a license too. Only series a customer can open (ProductLine.customer_reachable,
  # the gate's own scope). A fixed number of queries whatever the number of series.
  def load_series_in_use
    active = @active_licenses
    lines = ProductLine.customer_reachable.where(product_id: active.keys)
      .includes(:product, cover_image_attachment: :blob).to_a
    @series_in_use = lines.sort_by { |line| [ -active[line.product_id].map(&:starts_on).max.jd, line.id ] }
    # The license whose period the card shows: an indefinite one if there is one, else the latest end.
    @series_licenses = lines.to_h do |line|
      [ line.id, License.longest_running(active[line.product_id]) ]
    end

    # Handoff 0089 -- the card is the /products card (공개 N편 only; no first-episode button, no 공개 예정 count).
    ids = lines.map(&:id)
    @series_published_counts = ContentEpisode.published.where(product_line_id: ids).group(:product_line_id).count
    # Handoff 0090 -- the card jumps to the series page's 에피소드 section when the page has one: published or
    # 공개 예정 episodes, the same rule that draws it (ProductLinesHelper#series_episode_section?).
    upcoming_ids = ContentEpisode.upcoming(ContentEpisode.where(product_line_id: ids)).map(&:product_line_id)
    @series_with_episode_section = (@series_published_counts.select { |_, count| count.positive? }.keys + upcoming_ids).to_set
  end

  # Handoff 0085 R1 -- an earlier (standalone, paid) product the member holds a license usable right now
  # (License#active_at?, the check Entitlements::ProductAccess and the chapter gate make; scheduled-only or ended
  # licenses don't count). It no longer depends on the product being on sale: with sale_enabled off or every offer
  # off the license still opens the chapters (DocPolicy#view_as_license?). It does need the product active --
  # ProductContentController#enforce_active_product 404s an inactive product's chapters even for a license holder,
  # so a card there would lead nowhere.
  def legacy_products_in_use
    Product.standalone.active.where(free_access: false, id: @active_licenses.keys).order(:code).to_a
  end

  # Handoff 0085 R1 -- 다른 콘텐츠 (더 둘러보기 until 0089): the series on /products (ProductLine.listed, the same order) the member isn't
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
end
