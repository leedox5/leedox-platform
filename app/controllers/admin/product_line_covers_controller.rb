# Handoff 0056 R5 -- admin-only cover image display (draft products included)
# and the explicit "delete cover image" action.
# Admin::BaseController already restricts this namespace to admins.
class Admin::ProductLineCoversController < Admin::BaseController
  include CoverImageResponse

  before_action :set_product_line

  def show
    send_cover_variant(@product_line, params[:variant], cache: :revalidate)
  end

  # Purges synchronously (attachment, blob, stored file and its variants'
  # records) and clears the alt text so the "alt required only with an image"
  # rule stays consistent. The only path that removes a cover; irreversible.
  def destroy
    return head :not_found unless @product_line.cover_image.attached?

    filename = @product_line.cover_image.filename.to_s
    @product_line.cover_image.purge
    @product_line.update_columns(cover_image_alt: nil, updated_at: Time.current)
    redirect_to edit_admin_product_line_path(@product_line), notice: "\"#{@product_line.customer_name}\"의 대표 이미지(#{filename})를 삭제했습니다."
  end

  private

  def set_product_line
    @product_line = ProductLine.find(params[:product_line_id])
  end
end
