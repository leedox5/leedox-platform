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

    send_image_variant(product_line.cover_image, variant_name, cache: cache, label: "cover of ProductLine #{product_line.id}")
  end

  # Handoff 0063 -- the same delivery for any attached image (a ContentImage
  # too): only the named re-encoded variant is ever sent, headers and the
  # storage-outage handling stay identical. The caller has already checked
  # that the variant name is one it defines.
  def send_image_variant(attached, variant_name, cache:, label:)
    return head :not_found unless attached.attached?

    blob = attached.variant(variant_name.to_sym).processed.image.blob
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Cache-Control"] = cache == :short ? "private, max-age=300" : "private, no-cache"
    return unless stale?(etag: blob.checksum, public: false)

    send_data blob.download, type: blob.content_type, disposition: "inline"
  rescue Vips::Error, ActiveStorage::FileNotFoundError, ActiveStorage::InvariableError => e
    Rails.logger.error("Image variant #{variant_name} of #{label} failed: #{e.class}: #{e.message}")
    head :not_found
  rescue StandardError => e
    if StorageFailures.missing_error?(e)
      Rails.logger.error("[storage] image file missing for #{label}: #{e.class}")
      return head(:not_found)
    end
    raise unless StorageFailures.storage_error?(e)

    # Storage outage (bucket unreachable, credentials, provider error): the
    # image is temporarily unavailable, not gone -- 503 with a retry hint.
    Rails.logger.error("[storage] storage unavailable serving #{label}: #{e.class}: #{e.message}")
    response.headers["Retry-After"] = "30"
    head :service_unavailable
  end
end
