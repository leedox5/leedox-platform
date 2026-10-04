class PagesController < ApplicationController
  # Handoff 0071 -- the story-series home (D-009): featured series, new / coming episodes,
  # per-track rows (the AI row also carries the four standalone products) and the fixed
  # brand / series-season-episode blocks.
  def home
    # The standalone products, in /pricing's own order (pricing_rank) and with /pricing's own
    # sale-state rule (StandaloneProductsHelper) -- the home adds no rule of its own.
    @standalone_products = home_standalone_products
    load_story_series
    load_episode_updates
    load_home_notice
  end

  def chatdox
    # Pricing is rendered by shared/_product_pricing, which looks up the
    # product/offers/sales-enabled state itself from product_code alone.
  end

  def aigravity; end

  def getting_started; end

  def pricing
    @products = Product.standalone.order(:code).sort_by { |product| [ pricing_rank(product), product.code ] }
  end

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

  # /pricing's card order (handoff 0019): on sale first, then free, then
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
    @featured_line = ProductLine.listed.find_by(featured: true)
    track_lines = ProductLine.listed.where(track: ProductLine::TRACKS.keys).order(:id)
      .includes(:product, cover_image_attachment: :blob).to_a
    # Same order as /products (oldest first); a track with nothing in it is dropped entirely. The AI
    # row also carries the standalone products after its series (handoff 0071 e).
    @track_rows = ProductLine::TRACKS.keys.filter_map do |track|
      lines = track_lines.select { |line| line.track == track }
      extras = track == "ai" ? @standalone_products : []
      [ track, lines, extras ] if lines.any? || extras.any?
    end

    lines = [ @featured_line, *track_lines ].compact.uniq
    ids = lines.map(&:id)
    @series_access_states = lines.to_h { |line| [ line.id, line.access_state(owned: line.owned_by?(current_user)) ] }
    @published_counts = ContentEpisode.published.where(product_line_id: ids).group(:product_line_id).count
    @upcoming_counts = ContentEpisode.upcoming(ContentEpisode.where(product_line_id: ids)).group_by(&:product_line_id).transform_values(&:size)

    return unless @featured_line

    @featured_published = @featured_line.published_episodes.to_a
    @featured_upcoming = @featured_line.upcoming_episodes
  end

  UPDATES_LIMIT = 5
  UPDATES_UPCOMING_SLOTS = 2

  # Handoff 0071 (d) -- "새로 공개 · 공개 예정": up to 5 episodes of listed series, newest
  # published first (by published_at -- set when an episode is published; updated_at only for an
  # episode that somehow has none), then 공개 예정 ones (the 0070 rule). Two of the five are kept
  # for 공개 예정 when there are that many, so a steady stream of new episodes can't push the
  # "coming" half off the row entirely; either half fills the other's unused slots.
  def load_episode_updates
    listed = ProductLine.listed.select(:id)
    published = ContentEpisode.published.where(product_line_id: listed).includes(:product_line)
      .order(Arel.sql("COALESCE(content_episodes.published_at, content_episodes.updated_at) DESC"), :id)
      .limit(UPDATES_LIMIT).to_a
    upcoming = ContentEpisode.upcoming(ContentEpisode.where(product_line_id: listed).includes(:product_line))
      .sort_by { |episode| [ episode.product_line_id, episode.position ] }

    upcoming_taken = [ upcoming.size, UPDATES_UPCOMING_SLOTS, UPDATES_LIMIT ].min
    published_taken = [ published.size, UPDATES_LIMIT - upcoming_taken ].min
    upcoming_taken = [ upcoming.size, UPDATES_LIMIT - published_taken ].min
    @episode_updates = published.first(published_taken).map { |episode| [ :published, episode ] } +
      upcoming.first(upcoming_taken).map { |episode| [ :upcoming, episode ] }
  end
end
