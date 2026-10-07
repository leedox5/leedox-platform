class PagesController < ApplicationController
  # Handoff 0071 -- the story-series home (D-009): featured series and per-track rows (the AI row also carries the
  # standalone products). Handoff 0098 -- content only; the brand sentence and the 가이드 · 에피소드 · 실전 blocks
  # moved to /about.
  def home
    # The standalone products, in the old /pricing order (pricing_rank) and with its sale-state rule
    # (StandaloneProductsHelper) -- the home adds no rule of its own. The pricing page itself is gone (0086).
    @standalone_products = home_standalone_products
    load_story_series
    load_home_notice
  end

  def chatdox
    # Pricing is rendered by shared/_product_pricing, which looks up the
    # product/offers/sales-enabled state itself from product_code alone.
  end

  def aigravity; end

  # Handoff 0098 -- the about page: fixed copy, nothing to load.
  def about; end

  def getting_started; end

  def community; end

  def login; end

  def terms; end

  def privacy; end

  private

  # Handoff 0078 -- the AI row's standalone products: only those switched on for the home, in
  # /pricing's order (pricing_rank). Same single query as before plus one condition. If the column
  # isn't there yet (between deploy and migrate) the row just goes without them for that window
  # rather than taking the home down.
  def home_standalone_products
    Product.on_home.order(:code).to_a.sort_by { |product| [ pricing_rank(product), product.code ] }
  rescue StandardError => e
    Rails.logger.warn("[home_products] not loaded: #{e.class}: #{e.message}")
    []
  end

  # Handoff 0077 R2 -- the published + pinned notice the home announces in one line, or nil (no
  # line at all). One query, no Rails.cache (broken in production, backlog 0058). Best-effort like
  # the view counter (0073) and comments (0074): if it can't be loaded -- e.g. the table doesn't
  # exist yet between deploy and migrate -- the home renders without the line.
  def load_home_notice
    @home_notice = Announcement.home_pick
  rescue StandardError => e
    Rails.logger.warn("[home_notice] not loaded: #{e.class}: #{e.message}")
    @home_notice = nil
  end

  # The standalone products' card order (handoff 0019, first for /pricing; the home's AI row since 0071 and
  # the only user since the pricing page went in 0086): on sale first, then free, then
  # everything still prepping -- ahead of the plain code-alphabetical order,
  # so a not-yet-purchasable product (e.g. Antigravity) never happens to
  # sort ahead of what's actually buyable right now.
  def pricing_rank(product)
    return 0 if Commerce::Sales.enabled_for?(product)
    return 1 if product.free_access?

    2
  end

  # Handoff 0071 -- the story-series home (D-009): the featured series (hero) and the
  # per-track rows. Every visibility/price rule is an existing one: ProductLine.listed (0068),
  # access_state/owned_by? (0068, the purchase box's own judgment) and the published /
  # "공개 예정" episode split (0070). Nothing here decides who may see what by itself.
  def load_story_series
    # Handoff 0097 -- up to three featured guides in the operator's order, under the operator's title.
    @featured_lines = ProductLine.home_featured
    @featured_title = SiteSetting.home_featured_title if @featured_lines.any?
    track_lines = ProductLine.listed.where(track: ProductLine::TRACKS.keys).order(:id)
      .includes(:product, cover_image_attachment: :blob).to_a
    # Same order as /products (oldest first); a track with nothing in it is dropped entirely. The AI
    # row also carries the standalone products after its series (handoff 0071 e).
    @track_rows = ProductLine::TRACKS.keys.filter_map do |track|
      lines = track_lines.select { |line| line.track == track }
      extras = track == "ai" ? @standalone_products : []
      [ track, lines, extras ] if lines.any? || extras.any?
    end

    lines = [ *@featured_lines, *track_lines ].uniq
    ids = lines.map(&:id)
    @series_access_states = lines.to_h { |line| [ line.id, line.access_state(owned: line.owned_by?(current_user)) ] }
    # Handoff 0096 -- the featured card and the track cards show "N편" = published episodes only (0 -> 공개 예정);
    # the 공개 예정 count, the featured series' episode lists and the "새로 공개 · 공개 예정" row went with the old hero.
    @published_counts = ContentEpisode.published.where(product_line_id: ids).group(:product_line_id).count
  end
end
