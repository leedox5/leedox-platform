# Handoff 0092 R4 (D-012) -- "읽은 뒤 이어 보기". The buttons at the end of an 열린 편, the guide page's 이용하기 for guests
# and the locked episode cards all come here: GET /products/:slug/continue[?to=NN].
#
#   guest                      -> sign in (Devise remembers this GET and brings them back here, also after sign-up)
#   already using the guide    -> straight to the destination
#   free guide, not started    -> a confirmation page; its button (POST) starts it and goes to the destination
#   paid guide, not bought     -> that guide's checkout (what happens after paying is unchanged)
#   free start / sale closed   -> the guide page (its access box explains)
#   guide not open to customers -> the same 404 as every other gate
#
# A GET never creates a license (a link, a prefetch or a shared URL can't start anything); the POST calls the very
# same free start the 이용하기 button uses (Commerce::ClaimFreeAccess -- one license per user, a repeat is harmless).
# The destination never leaves the guide: ?to= counts only as a published episode number of this guide; anything
# else means the guide's episode list.
class GuideContinuationsController < ApplicationController
  include ProductLineGates

  before_action :load_product_line
  before_action :authenticate_user!

  def show
    return redirect_to(destination) if full_episode_access?
    return render(:show) if @product_line.free? && @product_line.free_start_open?
    return redirect_to(billing_checkout_path_for(@product_line.product.code)) if @product_line.for_sale?

    redirect_to product_line_path(@product_line.slug)
  end

  def create
    return redirect_to(destination) if full_episode_access?

    result = Commerce::ClaimFreeAccess.call!(user: current_user, product_line: @product_line)
    redirect_to destination, notice: result.created ? "이용을 시작했습니다." : nil
  rescue Commerce::ClaimFreeAccess::Unavailable
    redirect_to product_line_path(@product_line.slug), alert: "지금은 시작할 수 없습니다."
  end

  private

  def destination
    episode = target_episode
    episode ? product_episode_path(@product_line.slug, episode.display_id) : product_line_path(@product_line.slug, anchor: ProductLinesHelper::SERIES_SECTION_IDS[:episodes])
  end

  # The ?to= episode: a published episode of this guide, by its number -- nothing else.
  def target_episode
    to = params[:to].to_s
    return nil unless to.match?(/\A\d{1,4}\z/)

    @target_episode ||= @product_line.content_episodes.published.ordered.to_a.find { |episode| matches_display_id?(episode, to) }
  end
  helper_method :target_episode
end
