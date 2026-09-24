# Handoff 0058.
#
# 1. Blob deletion runs inline instead of through the job queue. Solid Queue's
#    database lives in the container's own storage/ and is reset on every
#    deploy, so a queued purge could be lost and leave the file behind in the
#    bucket. Running it inline (right after the record's transaction commits)
#    can't be lost. A storage failure while deleting is logged, never raised:
#    the record is already gone, and `rails storage:audit` reports leftovers.
Rails.application.config.to_prepare do
  ActiveStorage::PurgeJob.queue_adapter = :inline
  ActiveStorage::PurgeJob.rescue_from(StandardError) do |error|
    raise error unless StorageFailures.storage_error?(error)

    Rails.logger.error("[storage] blob purge failed, object may remain in storage: #{error.class}: #{error.message}")
  end
end

# 1b. Blob analysis runs inline for the same reason. Nothing in production runs a
#    job worker and the Solid Queue tables do not exist there (the SQLite queue
#    file is empty on every deploy, and the web process is started without
#    `db:prepare`), so enqueuing ActiveStorage::AnalyzeJob raised "Could not find
#    table 'solid_queue_jobs'" -- after the upload and the record were already
#    saved -- and turned every cover save and every first render of a new image
#    variant into a 500. Analysis is a few milliseconds of libvips on a file that
#    was just written (and ProductLine already analyzes its cover synchronously),
#    so running it inline costs nothing and can't be lost.
Rails.application.config.to_prepare do
  ActiveStorage::AnalyzeJob.queue_adapter = :inline
end

# 2. Say so loudly at boot when production is still on the container disk.
Rails.application.config.after_initialize do
  if Rails.env.production? && Rails.application.config.active_storage.service.to_s == "local"
    Rails.logger.warn("[storage] production is using the container's local disk; uploads are refused until " \
                      "ACTIVE_STORAGE_SERVICE=railway_bucket (and the STORAGE_BUCKET_* variables) are set")
  end
end
