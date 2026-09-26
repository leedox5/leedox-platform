# Customer pages for a ProductLine and its Episodes (handoff 0056 R3; since 0065
# the ProductLine is the sellable unit and the Season layer is gone), entirely
# separate from ProductContentController (/content/...).
#
# Each level applies its own lifecycle gate and 404s (never redirects or hints)
# when it isn't met, so a draft product/episode is invisible even to someone who
# knows the slug:
#   ProductLine    -> status published AND visibility public/unlisted
#   ContentEpisode -> status published
#   (gated product -> an active license, for episode bodies and files)
# Admins preview drafts through the separate Admin::* preview actions; there
# is no query param or session flag here that opens a gate.
#
# File downloads live in ProductAssetDownloadsController and reuse the same
# gates (ProductLineGates).
class ProductLinesController < ApplicationController
  include ProductLineGates

  # "무료"/"유료" also include a product already owned in that same money sense (0068 R2),
  # so a purchased product doesn't vanish from every filter that isn't "내 제품". "mine" is
  # only ever a real filter for a signed-in user (see #index) -- a guest requesting it
  # falls back to "all", the same as any value FILTERS doesn't recognize.
  FILTERS = %w[free paid mine].freeze

  before_action :load_product_line, except: %i[index]
  before_action :load_episode, only: %i[episode]
  before_action :require_product_license, only: %i[episode]

  # Handoff 0068 -- the customer product list: every listed (public, published)
  # ProductLine, oldest first (same order as the admin list; there is no separate
  # position column). Preloads the cover image and commerce Product/offers so
  # rendering the list doesn't add a query per card for those; the published
  # episode count is one grouped query instead of one per card.
  #
  # access_state/owned_by? (the same judgment the purchase box uses) is computed once per
  # line here and reused for both the filter and the badge -- never recomputed per view,
  # which would double the queries lifetime_offer/owned_by? make.
  def index
    all_lines = ProductLine.listed.order(:id).includes(:product, cover_image_attachment: :blob).to_a
    @access_states = all_lines.to_h { |line| [ line.id, line.access_state(owned: line.owned_by?(current_user)) ] }
    @filter = FILTERS.include?(params[:filter]) && (params[:filter] != "mine" || user_signed_in?) ? params[:filter] : "all"
    @product_lines = filtered_lines(all_lines)
    @filter_counts = { "all" => all_lines.size }.merge(FILTERS.index_with { |f| filtered_lines(all_lines, f).size })
    @published_episode_counts = ContentEpisode.where(product_line_id: all_lines.map(&:id), status: "published")
      .group(:product_line_id).count
  end

  # The product page: introduction, what a visitor can do to get it (purchase
  # box), and the published episodes.
  def show
    @episodes = @product_line.content_episodes.published.ordered
    @owned = @product_line.owned_by?(current_user)
    # Files of a paid product are listed only for owners (downloads are gated
    # separately in ProductAssetDownloadsController regardless).
    @assets_by_episode = if !@product_line.gated? || @owned
      ContentAsset.where(content_episode_id: @episodes.map(&:id)).ordered.with_attached_file.group_by(&:content_episode_id)
    else
      {}
    end
    @offer = @product_line.lifetime_offer if @product_line.gated?
    @for_sale = @product_line.for_sale?
    @free = @product_line.free?
    @free_open = @product_line.free_start_open?
  end

  def episode
    index = @episodes.index(@current_episode)
    @prev_episode = index.positive? ? @episodes[index - 1] : nil
    @next_episode = @episodes[index + 1]
    @content_html = ContentMarkdown.render(strip_leading_heading(@current_episode.body.to_s), parent: @current_episode)
    @takeaways = @current_episode.content_takeaways.ordered.map do |takeaway|
      { kind: takeaway.kind, body_html: ContentMarkdown.render(takeaway.body.to_s, parent: @current_episode) }
    end
    @assets = @current_episode.content_assets.ordered.with_attached_file
  end

  private

  # "free"/"paid" go by money, not by the exact badge: a product already owned counts as
  # whichever it was (free_open lines are 0-won, for_sale lines are priced), so buying
  # something doesn't drop it out of every filter except "내 제품".
  def filtered_lines(lines, filter = @filter)
    case filter
    when "free" then lines.select { |line| %i[free_open owned].include?(@access_states[line.id]) && line.free? }
    when "paid" then lines.select { |line| %i[for_sale owned].include?(@access_states[line.id]) && !line.free? }
    when "mine" then lines.select { |line| @access_states[line.id] == :owned }
    else lines
    end
  end

  def strip_leading_heading(raw_markdown)
    raw_markdown.sub(/\A\s*#[^\n]*\n?/, "")
  end
end
