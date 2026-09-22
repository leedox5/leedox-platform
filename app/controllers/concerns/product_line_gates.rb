# The customer-facing lifecycle gates for ProductLine -> Episode (handoff 0056
# R3/R4, reduced from three levels to two in 0065 when the Season layer went
# away), shared by the page controller and the file download controller so a
# download can never be more permissive than the page it is linked from:
#   ProductLine    -> published AND visibility public/unlisted
#   ContentEpisode -> published
# Any failed gate renders the same 404 (never a redirect or a hint).
#
# A ProductLine with a commerce Product (ProductLine#gated?) adds a third
# requirement for episode bodies and files: an active license for that Product
# (Entitlements::ProductAccess, the same check every paid product uses).
# Signed-out visitors are sent to sign in; signed-in users without the license
# are sent to the product page, where the purchase box is. Lines without a
# Product are unchanged (free, public).
module ProductLineGates
  extend ActiveSupport::Concern

  private

  def load_product_line
    @product_line = ProductLine.customer_reachable.find_by(slug: params[:product_slug])
    render_not_found if @product_line.nil?
  end

  def load_episode
    @episodes = @product_line.content_episodes.published.ordered.to_a
    @current_episode = @episodes.find { |episode| matches_display_id?(episode, params[:episode_id]) }
    render_not_found if @current_episode.nil?
  end

  def require_product_license
    return unless @product_line.gated?
    return if Entitlements::ProductAccess.allowed?(user: current_user, product_code: @product_line.product.code)

    authenticate_user!
    return if performed?

    redirect_to product_line_path(@product_line.slug), alert: "이 제품을 구매하면 볼 수 있습니다."
  end

  def render_not_found
    render plain: "아직 공개되지 않은 콘텐츠입니다.", status: :not_found
  end

  def matches_display_id?(episode, episode_id)
    id = episode_id.to_s
    episode.display_id == id || episode.display_id == id.rjust(2, "0")
  end
end
