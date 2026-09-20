# Sends an Active Storage blob as a download without ActiveStorage::Streaming.
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

  def send_blob_attachment(blob)
    response.headers["Content-Type"] = blob.content_type_for_serving
    response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(
      disposition: "attachment", filename: blob.filename.sanitized
    )
    response.headers["Content-Length"] = blob.byte_size.to_s
    response.headers["ETag"] = %("#{blob.checksum}")
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    self.response_body = Enumerator.new { |yielder| blob.download { |chunk| yielder << chunk } }
  end
end
