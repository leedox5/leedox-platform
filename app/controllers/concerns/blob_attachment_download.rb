# Sends an Active Storage blob as a download without ActiveStorage::Streaming
# (handoff 0058: works the same on the Disk and the bucket service).
#
# That module includes ActionController::Live, which runs the action in its
# own thread: Devise's `throw :warden` then escapes as a 500 instead of a
# sign-in redirect, and Rails' default security headers stop being applied.
# Instead the body is a lazy Enumerator over Blob#download (chunked reads, so a
# large file is never held in memory) served from the normal request thread.
#
# Always an attachment. The filename is Active Storage's sanitized form
# (path separators, quotes and control characters replaced) and content type
# is the "serving" type, which downgrades anything browsers would render
# (HTML/SVG/XML) to application/octet-stream. `private, no-store` because
# these responses are behind access gates; the explicit ETag also stops
# Rack::ETag from buffering the whole body to compute a digest.
module BlobAttachmentDownload
  extend ActiveSupport::Concern

  private

  # The file's existence is checked BEFORE any header or byte is sent: once
  # streaming has begun (Content-Length already promised) a missing object or a
  # storage outage could only produce a truncated/broken response. Missing ->
  # 404, storage unavailable -> 503; neither leaks the provider's message.
  def send_blob_attachment(blob)
    return render_missing_file(blob) unless blob.service.exist?(blob.key)

    response.headers["Content-Type"] = blob.content_type_for_serving
    response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(
      disposition: "attachment", filename: blob.filename.sanitized
    )
    response.headers["Content-Length"] = blob.byte_size.to_s
    response.headers["ETag"] = %("#{blob.checksum}")
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    self.response_body = Enumerator.new { |yielder| blob.download { |chunk| yielder << chunk } }
  rescue StandardError => error
    raise if response.committed?
    return render_missing_file(blob) if StorageFailures.missing_error?(error)
    raise unless StorageFailures.storage_error?(error)

    render_storage_unavailable(error, blob)
  end

  def render_missing_file(blob)
    Rails.logger.error("[storage] file missing for blob ##{blob.id} (#{blob.filename}); the database record exists but the stored file does not")
    render plain: StorageFailures::MISSING_MESSAGE, status: :not_found
  end

  def render_storage_unavailable(error, blob)
    Rails.logger.error("[storage] storage unavailable serving blob ##{blob.id}: #{error.class}: #{error.message}")
    response.headers["Retry-After"] = "30"
    render plain: StorageFailures::UNAVAILABLE_MESSAGE, status: :service_unavailable
  end
end
