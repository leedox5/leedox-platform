# Handoff 0065 (decision D5) -- the old Season URLs live on as permanent
# redirects. Before the flattening a page was /products/:line/:season[/:episode
# [/assets/:asset]]; every Season is now a product of its own, so the same
# content is /products/:new_line[/:episode[/assets/:asset]]. product_lines
# .legacy_season_id records which line each Season became.
#
# Like every gate on these pages, a target that a visitor could not open answers
# the same 404 as an unknown slug (never a redirect that would confirm a hidden
# product exists).
class LegacySeasonRedirectsController < ApplicationController
  def show
    target = target_line
    return head :not_found unless target&.customer_reachable?

    path = if params[:asset_id]
      product_episode_asset_path(target.slug, params[:episode_id], params[:asset_id])
    elsif params[:episode_id]
      product_episode_path(target.slug, params[:episode_id])
    else
      product_line_path(target.slug)
    end
    redirect_to path, status: :moved_permanently
  end

  private

  def target_line
    return unless ProductLine.column_names.include?("legacy_season_id")

    season = ProductSeason.joins(:product_line).find_by(slug: params[:season_slug].to_s, product_lines: { slug: params[:product_slug].to_s })
    season && ProductLine.find_by(legacy_season_id: season.id)
  end
end
