# The three customer-facing lifecycle gates for ProductLine -> ProductSeason ->
# Episode (handoff 0056 R3/R4), shared by the page controller and the file
# download controller so a download can never be more permissive than the
# page it is linked from:
#   ProductLine   -> status published
#   ProductSeason -> status published AND visibility public/unlisted
#   ContentEpisode -> status published
# Any failed gate renders the same 404 (never a redirect or a hint).
module ProductSeasonGates
  extend ActiveSupport::Concern

  private

  def load_product_line
    @product_line = ProductLine.published.find_by(slug: params[:product_slug])
    render_not_found if @product_line.nil?
  end

  def load_season
    @season = @product_line.product_seasons.customer_reachable.find_by(slug: params[:season_slug])
    render_not_found if @season.nil?
  end

  def load_episode
    @episodes = @season.content_episodes.published.ordered.to_a
    @current_episode = @episodes.find { |episode| matches_display_id?(episode, params[:episode_id]) }
    render_not_found if @current_episode.nil?
  end

  def render_not_found
    render plain: "아직 공개되지 않은 콘텐츠입니다.", status: :not_found
  end

  def matches_display_id?(episode, episode_id)
    id = episode_id.to_s
    episode.display_id == id || episode.display_id == id.rjust(2, "0")
  end
end
