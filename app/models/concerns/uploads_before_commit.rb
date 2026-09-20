# Handoff 0058 -- upload a new attachment INSIDE the save transaction.
#
# Active Storage's default uploads after the database commit. With a remote
# bucket that ordering is unsafe: if the upload then fails (outage, credentials)
# the record is already committed pointing at a file that was never stored, and
# on a replacement the record is repointed at the missing file. Uploading in an
# after_save callback instead makes a storage failure raise out of #save with
# the transaction rolled back, so nothing changes: no orphan record, and the
# previous file is left untouched (its purge only happens after a successful
# commit).
#
# Include AFTER the `has_one_attached` line so this callback runs after the one
# that persists the attachment and its blob.
module UploadsBeforeCommit
  extend ActiveSupport::Concern

  included do
    after_save :upload_pending_attachments_before_commit
  end

  private

  def upload_pending_attachments_before_commit
    attachment_changes.keys.each do |name|
      change = attachment_changes[name]
      next unless change.is_a?(ActiveStorage::Attached::Changes::CreateOne)

      change.upload
      # Uploaded now; stop Active Storage from uploading it a second time
      # after commit.
      attachment_changes.delete(name)
    end
  end
end
