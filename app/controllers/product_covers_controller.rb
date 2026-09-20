# Handoff 0056 R5 -- customer-facing cover image. Only a published ProductLine
# has a visible cover; a draft/unpublished product answers 404 exactly like
# its page does, so the image can't be fetched by someone who only knows the
# slug. The route is an application path (no Active Storage blob URL is
# rendered and Active Storage's own routes are off), so this check runs on
# every request that isn't a browser-cache revalidation hit.
class ProductCoversController < ApplicationController
  include CoverImageResponse

  def show
    product_line = ProductLine.published.find_by(slug: params[:product_slug])
    return head :not_found if product_line.nil?

    send_cover_variant(product_line, params[:variant], cache: :short)
  end
end
