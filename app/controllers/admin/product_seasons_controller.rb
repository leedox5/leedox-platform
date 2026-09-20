# Handoff 0056 R3 -- Season create/edit under a ProductLine, plus the
# admin-only preview of every Episode regardless of status. Episodes
# themselves are managed by Admin::ContentEpisodesController (shared with
# legacy Bundle episodes); a Season never exposes a Bundle or a parent-type
# choice.
class Admin::ProductSeasonsController < Admin::BaseController
  before_action :set_season, only: %i[show edit update]

  def show
    @episodes = @season.content_episodes.ordered
  end

  def new
    @product_line = ProductLine.find(params[:product_line_id])
    @season = @product_line.product_seasons.new
  end

  def create
    @product_line = ProductLine.find(params[:product_line_id])
    @season = @product_line.product_seasons.new(season_params)
    if @season.save
      redirect_to edit_admin_product_season_path(@season), notice: "Season을 만들었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @episodes = @season.content_episodes.ordered
  end

  def update
    if @season.update(season_params)
      redirect_to edit_admin_product_season_path(@season), notice: "저장했습니다."
    else
      @episodes = @season.content_episodes.ordered
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_season
    @season = ProductSeason.find(params[:id])
    @product_line = @season.product_line
  end

  def season_params
    params.require(:product_season).permit(:internal_name, :customer_title, :season_code, :slug, :status, :visibility, :position)
  end
end
