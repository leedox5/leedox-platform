# Handoff 0074 R2 -- the admin side of episode comments: every series' comments newest first, and
# hide / unhide. Admins never delete someone else's comment -- hiding is reversible (hidden_at);
# their own comments they delete like anyone (EpisodeCommentsController#destroy).
#
# Hide/unhide is reachable from this list and from the customer episode page; `from=episode`
# brings the admin back to the comment on that page (without counting it as an episode view).
class Admin::EpisodeCommentsController < Admin::BaseController
  LIST_LIMIT = 200

  def index
    @comments = EpisodeComment.order(created_at: :desc, id: :desc).limit(LIST_LIMIT)
      .includes(:user, content_episode: :product_line).to_a
    @total_count = EpisodeComment.count
  end

  def hide
    update_hidden(Time.current, "댓글을 숨겼습니다.")
  end

  def unhide
    update_hidden(nil, "숨김을 해제했습니다.")
  end

  private

  def update_hidden(hidden_at, notice)
    comment = EpisodeComment.find(params[:id])
    comment.update_columns(hidden_at: hidden_at, updated_at: Time.current)
    episode = comment.content_episode
    if params[:from] == "episode" && episode.product_line
      flash[EpisodeViewTracking::SKIP_FLASH] = episode.id
      redirect_to product_episode_path(episode.product_line.slug, episode.display_id, anchor: "comment-#{comment.id}"), notice: notice
    else
      redirect_to admin_episode_comments_path(anchor: "comment-#{comment.id}"), notice: notice
    end
  end
end
