# Handoff 0056 R3 -- customer pages for ProductLine -> ProductSeason ->
# Episode, entirely separate from ProductContentController (/content/...).
#
# Every level applies its own lifecycle gate and 404s (never redirects or
# hints) when it isn't met, so a draft product/season/episode is invisible
# even to someone who knows the slug:
#   ProductLine  -> status published
#   ProductSeason -> status published AND visibility public/unlisted
#                    (only public ones are *listed* on the product page)
#   ContentEpisode -> status published
# Admins preview drafts through the separate Admin::* preview actions; there
# is no query param or session flag here that opens a gate.
#
# File downloads live in ProductAssetDownloadsController and reuse the same
# gates (ProductSeasonGates).
#
# No License/purchase check yet -- published content is public until the
# later commerce round wires Seasons to a commerce Product.
class ProductLinesController < ApplicationController
  include MarkdownChecklistRendering
  include ProductSeasonGates

  before_action :load_product_line
  before_action :load_season, only: %i[season episode]
  before_action :load_episode, only: %i[episode]
  before_action :require_season_license, only: %i[episode]

  def show
    @seasons = @product_line.product_seasons.customer_listed.ordered
    # Handoff 0059 price summary: only what a visitor could actually get right now.
    @summary_seasons = @seasons.select(&:acquirable?)
  end

  def season
    @episodes = @season.content_episodes.published.ordered
    @owned = season_owned?
    # Files of a paid Season are listed only for owners (downloads are gated
    # separately in ProductAssetDownloadsController regardless).
    @assets_by_episode = if !@season.gated? || @owned
      ContentAsset.where(content_episode_id: @episodes.map(&:id)).ordered.with_attached_file.group_by(&:content_episode_id)
    else
      {}
    end
    @offer = @season.lifetime_offer if @season.gated?
    @for_sale = @season.for_sale?
    @free = @season.free?
    @free_open = @season.free_start_open?
  end

  def episode
    index = @episodes.index(@current_episode)
    @prev_episode = index.positive? ? @episodes[index - 1] : nil
    @next_episode = @episodes[index + 1]
    @content_html = render_markdown(strip_leading_heading(@current_episode.body.to_s))
    @takeaways = @current_episode.content_takeaways.ordered.map do |takeaway|
      { kind: takeaway.kind, body_html: render_markdown(takeaway.body.to_s) }
    end
    @assets = @current_episode.content_assets.ordered.with_attached_file
  end

  private

  def season_owned?
    @season.gated? && user_signed_in? &&
      Entitlements::ProductAccess.allowed?(user: current_user, product_code: @season.product.code)
  end

  def strip_leading_heading(raw_markdown)
    raw_markdown.sub(/\A\s*#[^\n]*\n?/, "")
  end

  def render_markdown(raw_markdown)
    html = Redcarpet::Markdown.new(
      Redcarpet::Render::HTML.new,
      autolink: true, tables: true, fenced_code_blocks: true, strikethrough: true, superscript: true
    ).render(raw_markdown)
    render_checklist_items(html).html_safe
  end
end
