require "digest"
require "securerandom"
require "stringio"
require "active_storage/service/disk_service" # not autoloaded when only the bucket service is configured

# Operator checks for the file storage (handoff 0058), used by
# `bin/rails storage:check` and `bin/rails storage:audit`. Nothing here deletes
# or changes real files: #round_trip writes and removes one throwaway object
# under its own prefix, #audit only reads.
class StorageVerifier
  CHECK_PREFIX = "storage-check/".freeze

  RoundTrip = Data.define(:ok, :steps, :service_name, :service_class)
  Audit = Data.define(:blob_count, :missing, :checksum_mismatch, :orphan_objects, :checksummed, :listing_supported)

  def initialize(service: ActiveStorage::Blob.service)
    @service = service
  end

  # Upload a small random object, confirm it exists, read it back and compare
  # its checksum, delete it, confirm it is gone.
  def round_trip
    key = "#{CHECK_PREFIX}#{SecureRandom.uuid}"
    data = SecureRandom.random_bytes(2048)
    checksum = Digest::MD5.base64digest(data)
    steps = []
    step = ->(name, &block) { steps << [ name, safely { block.call } ] }

    step.call("upload") { @service.upload(key, StringIO.new(data), checksum: checksum); true }
    step.call("exists") { exist?(key) }
    step.call("download matches checksum") { Digest::MD5.base64digest(@service.download(key)) == checksum }
    step.call("delete") { @service.delete(key); true }
    step.call("gone after delete") { !exist?(key) }

    RoundTrip.new(ok: steps.all? { |_, result| result == true }, steps: steps,
                  service_name: @service.name.to_s, service_class: @service.class.name)
  ensure
    safely { @service.delete(key) } if key
  end

  # Every Blob row must have its file; with checksum: true each file is also
  # downloaded and compared to the stored checksum. Objects in storage with no
  # Blob row (e.g. a purge that failed) are listed as orphans where the
  # service can be listed.
  def audit(checksum: false)
    missing = []
    mismatched = []
    known_keys = []
    ActiveStorage::Blob.find_each do |blob|
      next unless blob.service == @service

      known_keys << blob.key
      unless exist?(blob.key)
        missing << blob
        next
      end
      mismatched << blob if checksum && Digest::MD5.base64digest(@service.download(blob.key)) != blob.checksum
    end

    listing = listable_keys
    orphans = listing ? (listing - known_keys).reject { |key| key.start_with?(CHECK_PREFIX) } : []
    Audit.new(blob_count: known_keys.size, missing: missing, checksum_mismatch: mismatched,
              orphan_objects: orphans, checksummed: checksum, listing_supported: !listing.nil?)
  end

  private

  # Some S3 clients answer "no such object" with false, others by raising
  # NotFound; both mean the object is absent.
  def exist?(key)
    @service.exist?(key)
  rescue StandardError => e
    raise unless StorageFailures.missing_error?(e)

    false
  end

  def safely
    yield
  rescue StandardError => e
    "#{e.class}: #{e.message}".truncate(160)
  end

  def listable_keys
    if @service.respond_to?(:bucket)
      @service.bucket.objects.map(&:key)
    elsif @service.is_a?(ActiveStorage::Service::DiskService)
      # The Disk root may share a folder with unrelated files (SQLite
      # databases, ...); only "xx/yy/<key>" paths are Active Storage objects.
      root = @service.root.to_s
      Dir.glob(File.join(root, "*", "*", "*")).select { |path| File.file?(path) }.filter_map do |path|
        key = File.basename(path)
        key if path == File.join(root, key[0..1], key[2..3], key)
      end
    end
  end
end
