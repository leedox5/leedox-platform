# Sends a ProductLine cover image *variant* inline (handoff 0056 R5).
#
# Only the re-encoded `hero` / `thumb` variants (ProductLine::COVER_VARIANTS)
# are ever sent -- never the uploaded original -- so whatever a file claimed
# to be, the browser only receives our own libvips-encoded still image. The
# variant is processed once and stored by Active Storage (variant records),
# not recomputed per request.
#
# Deliberately not shared with ContentAsset's BlobAttachmentDownload: that is
# an access-gated attachment download, this is inline display of a derived
# image, and the two should be free to diverge.
module CoverImageResponse
  extend ActiveSupport::Concern

  private

  # cache: :revalidate keeps every request under the caller's access check
  # (admin previews); :short lets a browser reuse the image for a few minutes.
  def send_cover_variant(product_line, variant_name, cache:)
    return head :not_found unless ProductLine::COVER_VARIANTS.include?(variant_name.to_s)
    return head :not_found unless product_line.cover_image.attached?

    blob = product_line.cover_image.variant(variant_name.to_sym).processed.image.blob
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Cache-Control"] = cache == :short ? "private, max-age=300" : "private, no-cache"
    return unless stale?(etag: blob.checksum, public: false)

    send_data blob.download, type: blob.content_type, disposition: "inline"
  rescue Vips::Error, ActiveStorage::FileNotFoundError, ActiveStorage::InvariableError => e
    Rails.logger.error("Cover variant #{variant_name} for ProductLine #{product_line.id} failed: #{e.class}: #{e.message}")
    head :not_found
  rescue StandardError => e
    if StorageFailures.missing_error?(e)
      Rails.logger.error("[storage] cover file missing for ProductLine #{product_line.id}: #{e.class}")
      return head(:not_found)
    end
    raise unless StorageFailures.storage_error?(e)

    # Storage outage (bucket unreachable, credentials, provider error): the
    # image is temporarily unavailable, not gone -- 503 with a retry hint.
    Rails.logger.error("[storage] storage unavailable serving cover of ProductLine #{product_line.id}: #{e.class}: #{e.message}")
    response.headers["Retry-After"] = "30"
    head :service_unavailable
  end
end
