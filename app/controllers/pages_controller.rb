class PagesController < ApplicationController
  def home
    products = Product.standalone.active.to_a.sort_by(&:display_order)
    @flagship_products = products.reject(&:gateway?)
    @gateway_product = products.find(&:gateway?) || Product.find_by(code: "aistart")
    load_story_series
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
    # Same order as /products (oldest first); a track with no series is dropped entirely.
    @track_rows = ProductLine::TRACKS.keys.filter_map do |track|
      lines = track_lines.select { |line| line.track == track }
      [ track, lines ] if lines.any?
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
end
