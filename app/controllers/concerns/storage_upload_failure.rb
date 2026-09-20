# Handoff 0058 -- what an admin sees when the file bucket is unreachable while
# saving an upload. The model saves and uploads in one transaction
# (UploadsBeforeCommit), so a storage outage has already rolled everything
# back: nothing was saved and any previous file is untouched. The form is shown
# again with a plain "try again" message (503), never the provider's error.
module StorageUploadFailure
  extend ActiveSupport::Concern

  private

  def storage_upload_failed?(error)
    StorageFailures.storage_error?(error)
  end

  def render_storage_upload_failure(error, record:, attribute:, view:)
    Rails.logger.error("[storage] upload failed, nothing saved: #{error.class}: #{error.message}")
    record.errors.add(attribute, StorageFailures::UNAVAILABLE_MESSAGE)
    render view, status: :service_unavailable
  end
end
