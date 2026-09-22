# Handoff 0056 R4 -- the only way a customer can fetch an uploaded file.
#
# Runs the same lifecycle gates as the pages (ProductLineGates) and
# additionally requires the asset to belong to the episode named in the URL,
# so an asset id can't be replayed under another episode or product. The
# file is always sent as an attachment. No Active Storage blob URL is ever
# rendered and Active Storage's own routes are switched off
# (config.active_storage.draw_routes), so there is no path around these gates.
#
# Streaming goes through BlobAttachmentDownload (see there for why not
# ActiveStorage::Streaming).
class ProductAssetDownloadsController < ApplicationController
  include BlobAttachmentDownload
  include ProductLineGates

  before_action :load_product_line
  before_action :load_episode
  before_action :require_product_license

  def show
    asset = @current_episode.content_assets.find_by(id: params[:asset_id])
    return render_not_found if asset.nil? || !asset.file.attached?

    send_blob_attachment asset.file.blob
  end
end
