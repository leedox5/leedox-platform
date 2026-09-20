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

# 2. Say so loudly at boot when production is still on the container disk.
Rails.application.config.after_initialize do
  if Rails.env.production? && Rails.application.config.active_storage.service.to_s == "local"
    Rails.logger.warn("[storage] production is using the container's local disk; uploads are refused until " \
                      "ACTIVE_STORAGE_SERVICE=railway_bucket (and the STORAGE_BUCKET_* variables) are set")
  end
end
