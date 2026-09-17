class Admin::ContentTakeawaysController < Admin::BaseController
  before_action :set_takeaway, only: %i[edit update]

  def new
    @episode = ContentEpisode.find(params[:content_episode_id])
    @takeaway = @episode.content_takeaways.new
  end

  def create
    @episode = ContentEpisode.find(params[:content_episode_id])
    @takeaway = @episode.content_takeaways.new(takeaway_params)
    if @takeaway.save
      redirect_to edit_admin_content_episode_path(@episode), notice: "takeaway를 추가했습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @takeaway.update(takeaway_params)
      redirect_to edit_admin_content_episode_path(@takeaway.episode), notice: "저장했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_takeaway
    @takeaway = ContentTakeaway.find(params[:id])
    @episode = @takeaway.episode
  end

  def takeaway_params
    params.require(:content_takeaway).permit(:kind, :body, :position)
  end
end
