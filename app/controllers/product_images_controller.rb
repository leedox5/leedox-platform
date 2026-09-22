# Handoff 0063 -- customer delivery of an inline image (introduction or episode
# body). Every request re-checks the same gates as the page that shows the image
# (ContentImage#visible_to?), so an image is never reachable when its text is
# not: a draft product, an unpublished episode or a paid product without a
# license all answer 404, exactly like the page. The route is an application
# path -- no Active Storage blob URL is ever rendered.
class ProductImagesController < ApplicationController
  include CoverImageResponse

  def show
    return head :not_found unless ContentImage.table_exists?

    image = ContentImage.find_by(public_id: params[:public_id].to_s)
    return head :not_found unless image&.visible_to?(current_user)

    send_image_variant(image.file, "body", cache: image.cache_mode, label: "ContentImage #{image.id}")
  end
end
