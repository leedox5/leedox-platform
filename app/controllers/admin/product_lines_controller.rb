# Handoff 0056 R3 -- admin CRUD for ProductLine, the single entry point of
# the new-product flow (ProductLine -> Episode since handoff 0065).
# Admin::BaseController already restricts this whole namespace to
# authenticated admins.
class Admin::ProductLinesController < Admin::BaseController
  include StorageUploadFailure

  helper_method :episode_view_stats

  def index
    load_index
    @home_title = SiteSetting.home_featured_title_input
  end

  # Handoff 0097 -- the 홈 대표 섹션 box above the list: the title (blank = the default) and, for each featured guide,
  # its place 1..3 or "" to take it off the home. Both are saved together; a problem with either saves nothing and
  # shows the box again with what was typed.
  def home_featured
    @home_title = params[:home_title].to_s
    positions = params.fetch(:positions, {}).permit!.to_h
    error = nil
    ActiveRecord::Base.transaction do
      setting = SiteSetting.save_home_featured_title(@home_title)
      error = "섹션 제목은 #{SiteSetting::HOME_FEATURED_TITLE_MAX}자까지 쓸 수 있습니다." if setting.errors.any?
      error ||= ProductLine.arrange_featured!(positions)
      raise ActiveRecord::Rollback if error
    end

    if error
      load_index
      flash.now[:alert] = error
      render :index, status: :unprocessable_entity
    else
      redirect_to admin_product_lines_path, notice: "홈 대표 섹션을 저장했습니다."
    end
  end

  # Admin-only preview: shows the customer-facing product info and every
  # episode regardless of lifecycle state (the customer route only shows
  # published ones -- see ProductLinesController).
  def show
    @product_line = ProductLine.find(params[:id])
    @episodes = @product_line.content_episodes.ordered
  end

  def new
    @product_line = ProductLine.new
  end

  def create
    @product_line = ProductLine.new(product_line_params)
    if @product_line.save
      redirect_to edit_admin_product_line_path(@product_line), notice: "제품을 만들었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  rescue StandardError => e
    raise unless storage_upload_failed?(e)

    render_storage_upload_failure(e, record: @product_line, attribute: :cover_image, view: :new)
  end

  def edit
    @product_line = ProductLine.find(params[:id])
    @episodes = @product_line.content_episodes.ordered
  end

  def update
    @product_line = ProductLine.find(params[:id])
    if @product_line.update(product_line_params)
      redirect_to edit_admin_product_line_path(@product_line), notice: "저장했습니다."
    else
      @episodes = @product_line.content_episodes.ordered
      render :edit, status: :unprocessable_entity
    end
  rescue StandardError => e
    raise unless storage_upload_failed?(e)

    @episodes = @product_line.content_episodes.ordered
    render_storage_upload_failure(e, record: @product_line, attribute: :cover_image, view: :edit)
  end

  private

  def load_index
    @product_lines = ProductLine.order(:id).with_attached_cover_image
    # Handoff 0073 -- each series' views and people (all time / last 7 days), grouped queries for the whole list.
    @view_stats = EpisodeView.stats_by_product_line(@product_lines.map(&:id))
  end

  # Handoff 0073 -- per-episode views and people for the edit page's episode list (every path that renders
  # :edit sets @episodes first, so this is computed lazily from it rather than in each of them).
  def episode_view_stats
    @episode_view_stats ||= EpisodeView.stats_by_episode(@episodes.map(&:id))
  end

  def product_line_params
    params.require(:product_line).permit(:internal_name, :customer_name, :summary, :slug, :introduction, :ai_supporter, :status, :visibility, :series_key, :series_label, :series_position, :track, :featured, :cover_image, :cover_image_alt)
  end
end
