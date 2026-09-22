# Handoff 0056 R4 -- admin-only download of a product episode's file (any
# episode status, so drafts can be checked before publishing).
class Admin::ContentAssetDownloadsController < Admin::BaseController
  include BlobAttachmentDownload

  def show
    asset = ContentAsset.find(params[:id])
    return head :not_found unless asset.content_episode.product_line_id? && asset.file.attached?

    send_blob_attachment asset.file.blob
  end
end
