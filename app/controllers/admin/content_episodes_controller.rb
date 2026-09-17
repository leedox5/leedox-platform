# Handoff 0053 R3. #show here is the admin-only draft preview -- it queries
# ContentEpisode directly, completely separate from ProductContentController/
# ProductContent::DatabaseSource (which only ever returns published
# episodes, see result_r3.md §5). There is no shared code path or query
# param a non-admin request could use to reach a draft through this action,
# since Admin::BaseController already blocks non-admins from the whole
# namespace.
class Admin::ContentEpisodesController < Admin::BaseController
  before_action :set_episode, only: %i[edit update show publish unpublish]

  helper_method :render_preview_markdown

  def new
    @bundle = ContentBundle.find(params[:content_bundle_id])
    @episode = @bundle.content_episodes.new
  end

  def create
    @bundle = ContentBundle.find(params[:content_bundle_id])
    @episode = @bundle.content_episodes.new(episode_params)
    @episode.author = current_user
    if @episode.save
      redirect_to edit_admin_content_episode_path(@episode), notice: "편을 만들었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @takeaways = @episode.content_takeaways.ordered
  end

  def show
    @takeaways = @episode.content_takeaways.ordered
  end

  def update
    @episode.editor = current_user
    if @episode.update(episode_params)
      redirect_to edit_admin_content_episode_path(@episode), notice: "저장했습니다."
    else
      @takeaways = @episode.content_takeaways.ordered
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    # Someone else (or another tab/session) saved this episode after this
    # form was loaded -- the submitted lock_version no longer matches the
    # row's current one. Reload the real current state rather than silently
    # overwriting it (handoff 0053 R3 §4).
    @episode.reload
    @takeaways = @episode.content_takeaways.ordered
    flash.now[:alert] = "다른 곳에서 먼저 저장되어 최신 내용을 다시 불러왔습니다. 내용을 확인하고 다시 저장해주세요."
    render :edit, status: :conflict
  end

  def publish
    @episode.update!(status: "published", published_at: Time.current)
    redirect_to edit_admin_content_episode_path(@episode), notice: "게시했습니다."
  end

  def unpublish
    @episode.update!(status: "unpublished")
    redirect_to edit_admin_content_episode_path(@episode), notice: "비공개로 전환했습니다."
  end

  private

  # Plain rendering (no LinkRewritingRenderer) -- this is an admin-only
  # preview, not the customer-facing route, and DB episode bodies don't carry
  # the relative .md-link convention that renderer resolves.
  def render_preview_markdown(raw_markdown)
    Redcarpet::Markdown.new(Redcarpet::Render::HTML.new, autolink: true, tables: true, fenced_code_blocks: true).render(raw_markdown.to_s)
  end

  def set_episode
    @episode = ContentEpisode.find(params[:id])
    @bundle = @episode.bundle
  end

  def episode_params
    params.require(:content_episode).permit(:customer_title, :position, :body, :lock_version)
  end
end
