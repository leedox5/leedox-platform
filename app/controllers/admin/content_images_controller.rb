# Handoff 0063 -- upload, edit the alt text of, delete, and display (draft
# included) the inline images of a ProductLine introduction or an episode.
# Admin::BaseController already restricts this namespace to admins.
class Admin::ContentImagesController < Admin::BaseController
  include CoverImageResponse
  include StorageUploadFailure

  before_action :set_parent, only: :create
  before_action :set_image, only: %i[update destroy file]

  def create
    image = @parent.content_images.new(image_params)
    if image.save
      redirect_to parent_edit_path(@parent), notice: "이미지를 추가했습니다. 아래 목록의 '본문에 삽입'으로 글에 넣을 수 있습니다."
    else
      redirect_to parent_edit_path(@parent), alert: image.errors.full_messages.to_sentence
    end
  rescue StandardError => e
    raise unless storage_upload_failed?(e)

    # The upload happens inside the save's transaction, so nothing was saved.
    Rails.logger.error("[storage] image upload failed, nothing saved: #{e.class}: #{e.message}")
    redirect_to parent_edit_path(@parent), alert: StorageFailures::UNAVAILABLE_MESSAGE
  end

  def update
    if @image.update(params.fetch(:content_image, {}).permit(:alt))
      redirect_to parent_edit_path(@image.parent), notice: "대체문구를 저장했습니다."
    else
      redirect_to parent_edit_path(@image.parent), alert: @image.errors.full_messages.to_sentence
    end
  end

  # Purges synchronously (attachment, blob, stored file and variants) so the
  # object leaves the bucket now. Irreversible; a text that still names the
  # image just stops showing it (the preview says so).
  def destroy
    parent = @image.parent
    was_used = @image.referenced?
    @image.file.purge
    @image.destroy!
    notice = "이미지를 삭제했습니다."
    notice += " 글에 이 이미지를 넣은 부분이 남아 있으니 지워 주세요." if was_used
    redirect_to parent_edit_path(parent), notice: notice
  end

  def file
    return head :not_found unless ContentImage::VARIANTS.include?(params[:variant].to_s)

    send_image_variant(@image.file, params[:variant], cache: :revalidate, label: "ContentImage #{@image.id} (admin)")
  end

  private

  def set_parent
    @parent = if params[:product_line_id]
      ProductLine.find(params[:product_line_id])
    else
      ContentEpisode.find(params[:content_episode_id])
    end
  end

  def set_image
    @image = ContentImage.find_by!(public_id: params[:public_id].to_s)
  end

  def image_params
    params.fetch(:content_image, {}).permit(:file, :alt)
  end

  def parent_edit_path(parent)
    parent.is_a?(ProductLine) ? edit_admin_product_line_path(parent) : edit_admin_content_episode_path(parent)
  end
end
