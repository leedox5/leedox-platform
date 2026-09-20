# Operator checks for the file storage (handoff 0058). Read-only apart from
# `storage:check`'s own throwaway object. On production:
#   railway ssh --service web -- bin/rails storage:check
#   railway ssh --service web -- bin/rails storage:audit            (existence)
#   railway ssh --service web -- env CHECKSUM=1 bin/rails storage:audit
namespace :storage do
  desc "Round-trip a throwaway object through the configured file storage (upload, read back, checksum, delete)"
  task check: :environment do
    service = ActiveStorage::Blob.service
    puts "storage service : #{service.name} (#{service.class.name})"
    puts "configured      : ACTIVE_STORAGE_SERVICE=#{ENV['ACTIVE_STORAGE_SERVICE'].presence || '(unset -> local)'}"
    if service.respond_to?(:bucket)
      puts "bucket          : #{service.bucket.name}"
      puts "endpoint        : #{service.client.client.config.endpoint}"
      puts "region          : #{service.client.client.config.region}"
    end
    if StoragePersistence.upload_blocked? || (Rails.env.production? && service.is_a?(ActiveStorage::Service::DiskService))
      puts "WARNING: production is on the container's local disk -- files do NOT survive a deploy and uploads are refused."
    end

    result = StorageVerifier.new(service: service).round_trip
    result.steps.each { |name, outcome| puts format("  %-28s %s", name, outcome == true ? "ok" : "FAILED (#{outcome})") }
    puts result.ok ? "RESULT: PASS" : "RESULT: FAIL"
    exit(1) unless result.ok
  end

  desc "List stored files that are missing from storage and stored objects that have no record (CHECKSUM=1 also verifies checksums)"
  task audit: :environment do
    audit = StorageVerifier.new.audit(checksum: ENV["CHECKSUM"].present?)
    puts "storage service      : #{ActiveStorage::Blob.service.name}"
    puts "blob records         : #{audit.blob_count}"
    puts "missing files        : #{audit.missing.size}"
    audit.missing.each { |blob| puts "  blob ##{blob.id} #{blob.filename} (#{blob.byte_size} bytes)" }
    puts "checksum verified    : #{audit.checksummed ? 'yes' : 'no (set CHECKSUM=1)'}"
    puts "checksum mismatches  : #{audit.checksum_mismatch.size}"
    audit.checksum_mismatch.each { |blob| puts "  blob ##{blob.id} #{blob.filename}" }
    puts "orphan objects       : #{audit.listing_supported ? audit.orphan_objects.size : 'n/a (service cannot be listed)'}"
    audit.orphan_objects.each { |key| puts "  #{key}" }
    exit(1) if audit.missing.any? || audit.checksum_mismatch.any?
  end
end
