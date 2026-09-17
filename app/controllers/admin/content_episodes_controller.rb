# Handoff 0053 R3. #show here is the admin-only draft preview -- it queries
# ContentEpisode directly, completely separate from ProductContentController/
# ProductContent::DatabaseSource (which only ever returns published
# episodes, see result_r3.md §5). There is no shared code path or query
# param a non-admin request could use to reach a draft through this action,
# since Admin::BaseController already blocks non-admins from the whole
# namespace.
class Admin::ContentEpisodesController < Admin::BaseController
  include MarkdownChecklistRendering

  # Handoff 0054 R2 P0-1 -- any status may move to any other status except
  # itself (a self-transition is the one thing consistently meaningless
  # across every state, so it's the one case rejected).
  VALID_STATUSES = %w[draft in_review published unpublished].freeze

  before_action :set_episode, only: %i[edit update show transition publish unpublish destroy]

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
    # Unlike the customer path (ProductContent::DatabaseSource, published-only),
    # admin preview navigation walks every status in the bundle -- an editor
    # reviewing a draft needs to move between draft siblings too (handoff
    # 0054 R2 P0-2).
    siblings = @bundle.content_episodes.ordered.to_a
    current_index = siblings.index(@episode)
    @prev_episode = siblings[0...current_index]&.last
    @next_episode = siblings[(current_index + 1)..]&.first
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

  # #publish/#unpublish stay as their own routes for backward compatibility
  # with existing bookmarks/tests (handoff 0053), but now go through the
  # same validated path as the generic transition action instead of writing
  # status unconditionally.
  def transition
    apply_transition(params[:status])
  end

  def publish
    apply_transition("published")
  end

  def unpublish
    apply_transition("unpublished")
  end

  # Handoff 0055 follow-up -- deliberately the simplest possible operation:
  # no archive/trash/restore, no renumbering of the remaining episodes
  # (their position/body/status are untouched), and a bundle with zero or
  # one episode left is fine. content_takeaways/content_revisions cascade
  # via the existing `dependent: :destroy` associations on ContentEpisode
  # (see app/models/content_episode.rb) -- no new destroy logic needed for
  # those. The "irreversible" and "this is published" warnings live in the
  # confirm dialog on the edit view, not here -- this action doesn't
  # re-check status before destroying (published episodes can be deleted;
  # the warning is what's supposed to stop a careless click, not a second
  # server-side gate).
  def destroy
    bundle = @episode.bundle
    title = @episode.customer_title.presence || "(제목 없음)"
    @episode.destroy!
    redirect_to edit_admin_content_bundle_path(bundle), notice: "\"#{title}\" 편을 삭제했습니다."
  end

  private

  def apply_transition(target_status)
    unless VALID_STATUSES.include?(target_status)
      return redirect_to edit_admin_content_episode_path(@episode), alert: "알 수 없는 상태입니다."
    end

    if target_status == @episode.status
      return redirect_to edit_admin_content_episode_path(@episode), alert: "이미 #{target_status} 상태입니다."
    end

    attrs = { status: target_status }
    attrs[:published_at] = Time.current if target_status == "published"
    @episode.update!(attrs)
    redirect_to edit_admin_content_episode_path(@episode), notice: "#{target_status} 상태로 전환했습니다."
  end

  # Plain rendering (no LinkRewritingRenderer) -- this is an admin-only
  # preview, not the customer-facing route, and DB episode bodies don't carry
  # the relative .md-link convention that renderer resolves.
  def render_preview_markdown(raw_markdown)
    html = Redcarpet::Markdown.new(Redcarpet::Render::HTML.new, autolink: true, tables: true, fenced_code_blocks: true).render(raw_markdown.to_s)
    render_checklist_items(html)
  end

  def set_episode
    @episode = ContentEpisode.find(params[:id])
    @bundle = @episode.bundle
  end

  def episode_params
    params.require(:content_episode).permit(:customer_title, :position, :body, :lock_version, :internal_ref)
  end
end
