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

  before_action :load_product_line
  before_action :load_episode, only: %i[episode]
  before_action :require_product_license, only: %i[episode]

  # The product page: introduction, what a visitor can do to get it (purchase
  # box), and the published episodes.
  def show
    @episodes = @product_line.content_episodes.published.ordered
    @owned = product_owned?
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

  def product_owned?
    @product_line.gated? && user_signed_in? &&
      Entitlements::ProductAccess.allowed?(user: current_user, product_code: @product_line.product.code)
  end

  def strip_leading_heading(raw_markdown)
    raw_markdown.sub(/\A\s*#[^\n]*\n?/, "")
  end
end
