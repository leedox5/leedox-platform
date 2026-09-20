# Handoff 0056 R4 -- upload/replace/delete/download of files attached to a
# ProductSeason Episode. Admin::BaseController already restricts this whole
# namespace to authenticated admins.
#
# Assets are only managed for Season episodes; the shallow routes also
# resolve for legacy Bundle episodes (they share ContentEpisode), so
# #set_episode / #set_asset 404 those instead of relying on the UI merely
# not linking to them. Downloads are in Admin::ContentAssetDownloadsController.
class Admin::ContentAssetsController < Admin::BaseController
  include StorageUploadFailure

  before_action :set_asset, only: %i[edit update destroy]
  before_action :set_episode_from_params, only: %i[new create]

  def new
    @asset = @episode.content_assets.new(position: next_position)
  end

  def create
    @asset = @episode.content_assets.new(asset_params)
    if @asset.save
      redirect_to edit_admin_content_episode_path(@episode), notice: "산출물을 추가했습니다."
    else
      render :new, status: :unprocessable_entity
    end
  rescue StandardError => e
    raise unless storage_upload_failed?(e)

    render_storage_upload_failure(e, record: @asset, attribute: :file, view: :new)
  end

  def edit
  end

  def update
    if @asset.update(asset_params)
      redirect_to edit_admin_content_episode_path(@episode), notice: "저장했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  rescue StandardError => e
    raise unless storage_upload_failed?(e)

    render_storage_upload_failure(e, record: @asset, attribute: :file, view: :edit)
  end

  def destroy
    title = @asset.title
    filename = @asset.file.filename.to_s
    @asset.destroy!
    redirect_to edit_admin_content_episode_path(@episode), notice: "\"#{title}\" (#{filename}) 산출물을 삭제했습니다."
  end

  private

  def set_asset
    @asset = ContentAsset.find(params[:id])
    @episode = @asset.content_episode
    head :not_found unless @episode.product_season_id?
  end

  def set_episode_from_params
    @episode = ContentEpisode.find(params[:content_episode_id])
    head :not_found unless @episode.product_season_id?
  end

  def next_position
    (@episode.content_assets.maximum(:position) || 0) + 1
  end

  def asset_params
    params.require(:content_asset).permit(:title, :kind, :description, :position, :file)
  end
end
