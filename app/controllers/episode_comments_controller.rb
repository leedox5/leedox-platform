# Handoff 0074 -- writing and self-deleting comments under a customer episode page.
#
# Every request goes through the same gates as the episode page itself (ProductLineGates:
# reachable series, published episode, a license for a gated series), so someone who can't
# open the episode can't comment on it by posting to the URL either; on top of that, writing
# and deleting require a signed-in user. Only the author can delete, and only softly
# (EpisodeComment#soft_delete!).
#
# A rejected comment (blank, too long, a reply to a reply) re-renders the episode page with
# the text kept and the reason shown; a success redirects back to the new comment.
class EpisodeCommentsController < ApplicationController
  include ProductLineGates
  include EpisodePage

  before_action :load_product_line
  before_action :load_episode
  before_action :require_product_license
  before_action :authenticate_user!

  def create
    @new_comment = @current_episode.episode_comments.new(comment_params.merge(user: current_user))
    if EpisodeComment.rate_limited?(current_user)
      skip_next_episode_view
      redirect_to comments_anchor, alert: "잠시 후 다시 시도해 주세요."
    elsif @new_comment.save
      skip_next_episode_view
      redirect_to product_episode_path(@product_line.slug, @current_episode.display_id, anchor: "comment-#{@new_comment.id}")
    else
      prepare_episode_page
      render "product_lines/episode", status: :unprocessable_entity
    end
  end

  def destroy
    comment = @current_episode.episode_comments.find_by(id: params[:id])
    return head :not_found unless comment&.authored_by?(current_user)

    comment.soft_delete!
    skip_next_episode_view
    redirect_to comments_anchor, notice: "댓글을 삭제했습니다."
  end

  private

  def comment_params
    params.require(:episode_comment).permit(:body, :parent_id)
  end

  # 0074 R2 -- the redirect back to the episode isn't a view (see EpisodeViewTracking::SKIP_FLASH).
  def skip_next_episode_view
    flash[EpisodeViewTracking::SKIP_FLASH] = @current_episode.id
  end

  def comments_anchor
    product_episode_path(@product_line.slug, @current_episode.display_id, anchor: "comments")
  end
end
