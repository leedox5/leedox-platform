require "test_helper"
require "rake"
require "open3"
require_relative "../support/fake_bucket"

# Handoff 0058 -- the production bucket service configuration and the operator
# checks (`storage:check`, `storage:audit`).
class StorageConfigurationTest < ActiveSupport::TestCase
  ENV_NAMES = %w[
    STORAGE_BUCKET_NAME STORAGE_BUCKET_ENDPOINT STORAGE_BUCKET_REGION STORAGE_BUCKET_ACCESS_KEY_ID
    STORAGE_BUCKET_SECRET_ACCESS_KEY STORAGE_BUCKET_FORCE_PATH_STYLE
    AWS_S3_BUCKET_NAME AWS_ENDPOINT_URL AWS_DEFAULT_REGION AWS_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
  ].freeze

  setup do
    @previous = ENV_NAMES.to_h { |name| [ name, ENV[name] ] }
    ENV_NAMES.each { |name| ENV.delete(name) }
    Rails.application.load_tasks unless Rake::Task.task_defined?("storage:check")
  end

  teardown do
    @previous.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end

  def bucket_service
    configs = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/storage.yml")).deep_symbolize_keys
    ActiveStorage::Service.configure(:railway_bucket, configs)
  end

  def run_task(name)
    Rake::Task[name].reenable
    out = StringIO.new
    original = $stdout
    $stdout = out
    begin
      Rake::Task[name].invoke
      [ out.string, nil ]
    rescue SystemExit => e
      [ out.string, e.status ]
    ensure
      $stdout = original
    end
  end

  # --- storage.yml -----------------------------------------------------------

  test "the bucket service is a private S3 service built from STORAGE_BUCKET_* variables" do
    ENV.update("STORAGE_BUCKET_NAME" => "my-private-bucket", "STORAGE_BUCKET_ENDPOINT" => "https://storage.example.test",
               "STORAGE_BUCKET_REGION" => "sin", "STORAGE_BUCKET_ACCESS_KEY_ID" => "AKID-TEST", "STORAGE_BUCKET_SECRET_ACCESS_KEY" => "SECRET-TEST")
    service = bucket_service
    config = service.client.client.config

    assert_instance_of ActiveStorage::Service::S3Service, service
    assert_equal "my-private-bucket", service.bucket.name
    assert_equal "https://storage.example.test", config.endpoint.to_s
    assert_equal "sin", config.region
    assert_equal "AKID-TEST", config.credentials.credentials.access_key_id
    assert_not service.public?, "the bucket must never be public"
    assert_equal false, config.force_path_style
    assert_equal "when_required", config.request_checksum_calculation
    assert_equal "when_required", config.response_checksum_validation
  end

  test "the standard AWS-style variable names work too, and STORAGE_BUCKET_* wins when both are set" do
    ENV.update("AWS_S3_BUCKET_NAME" => "aws-named", "AWS_ENDPOINT_URL" => "https://aws-style.test", "AWS_DEFAULT_REGION" => "ap-southeast-1",
               "AWS_ACCESS_KEY_ID" => "AWS-AKID", "AWS_SECRET_ACCESS_KEY" => "AWS-SECRET")
    service = bucket_service
    assert_equal "aws-named", service.bucket.name
    assert_equal "https://aws-style.test", service.client.client.config.endpoint.to_s
    assert_equal "ap-southeast-1", service.client.client.config.region
    assert_equal "AWS-AKID", service.client.client.config.credentials.credentials.access_key_id

    ENV["STORAGE_BUCKET_NAME"] = "explicit"
    ENV["STORAGE_BUCKET_ACCESS_KEY_ID"] = "EXPLICIT-AKID"
    assert_equal "explicit", bucket_service.bucket.name
    assert_equal "EXPLICIT-AKID", bucket_service.client.client.config.credentials.credentials.access_key_id
  end

  test "region defaults to auto and path-style addressing is opt-in" do
    ENV.update("STORAGE_BUCKET_NAME" => "b", "STORAGE_BUCKET_ENDPOINT" => "https://s.test", "STORAGE_BUCKET_ACCESS_KEY_ID" => "a", "STORAGE_BUCKET_SECRET_ACCESS_KEY" => "s")
    assert_equal "auto", bucket_service.client.client.config.region
    assert_equal false, bucket_service.client.client.config.force_path_style
    ENV["STORAGE_BUCKET_FORCE_PATH_STYLE"] = "true"
    assert_equal true, bucket_service.client.client.config.force_path_style
  end

  test "storage.yml and production.rb hold no credential, only variable references" do
    yml = Rails.root.join("config/storage.yml").read
    bucket_section = yml[/^railway_bucket:.*/m]
    %w[bucket endpoint access_key_id secret_access_key].each do |setting|
      line = bucket_section.lines.find { |l| l.strip.start_with?("#{setting}:") }
      assert_includes line, "ENV[", "#{setting} must come from the environment"
    end
    assert_no_match(/[A-Za-z0-9\/+]{32,}/, bucket_section.lines.reject { |l| l.strip.start_with?("#") }.join)

    production = Rails.root.join("config/environments/production.rb").read
    assert_includes production, 'ENV.fetch("ACTIVE_STORAGE_SERVICE", "local")'
    assert_no_match(/secret_access_key|access_key_id/, production)
  end

  test "a real production boot with only the bucket configured works: the service resolves and the upload guard does not need the Disk class" do
    env = { "SECRET_KEY_BASE_DUMMY" => "1", "RAILS_ENV" => "production", "ACTIVE_STORAGE_SERVICE" => "railway_bucket",
            "STORAGE_BUCKET_NAME" => "dummy-bucket", "STORAGE_BUCKET_ENDPOINT" => "https://storage.invalid", "STORAGE_BUCKET_REGION" => "sin",
            "STORAGE_BUCKET_ACCESS_KEY_ID" => "dummy", "STORAGE_BUCKET_SECRET_ACCESS_KEY" => "dummy" }
    script = 's = ActiveStorage::Blob.service; puts [ s.class, s.bucket.name, s.public?, StoragePersistence.upload_blocked? ].join("|")'
    output, status = Open3.capture2e(env, Rails.root.join("bin/rails").to_s, "runner", script, chdir: Rails.root.to_s)
    assert status.success?, output
    assert_includes output.lines.last.to_s.strip, "ActiveStorage::Service::S3Service|dummy-bucket|false|false"

    output, status = Open3.capture2e(env.merge("ACTIVE_STORAGE_SERVICE" => "typo"), Rails.root.join("bin/rails").to_s, "runner", "ActiveStorage::Blob.service", chdir: Rails.root.to_s)
    assert_not status.success?, "a mistyped service name must fail loudly, not silently fall back to the local disk"
  end

  test "development and test keep the local Disk services (no bucket needed off production)" do
    configs = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/storage.yml")).deep_symbolize_keys
    assert_equal "Disk", configs[:local][:service]
    assert_equal "Disk", configs[:test][:service]
    assert_equal :test, Rails.application.config.active_storage.service
  end

  # --- StorageVerifier / rake tasks ---------------------------------------------

  test "round trip passes on the local Disk service and leaves nothing behind" do
    result = StorageVerifier.new.round_trip
    assert result.ok, result.steps.inspect
    assert_equal %w[upload exists download\ matches\ checksum delete gone\ after\ delete], result.steps.map(&:first)
  end

  test "round trip passes against the bucket service and cleans up its throwaway object" do
    bucket = FakeBucket.new
    bucket.install do
      result = StorageVerifier.new(service: bucket.service).round_trip
      assert result.ok, result.steps.inspect
      assert_empty bucket.keys
      assert_equal "S3Service", result.service_class.split("::").last
    end
  end

  test "round trip reports which step fails during an outage, never raises, and does not fake success" do
    bucket = FakeBucket.new
    bucket.install do
      bucket.outage = Aws::S3::Errors::ServiceUnavailable.new(nil, "down")
      result = StorageVerifier.new(service: bucket.service).round_trip
      assert_not result.ok
      assert_match(/ServiceUnavailable/, result.steps.first.last)
    end
  end

  test "audit: clean storage is clean; a missing file, a corrupted file and an orphan object are each reported, and nothing is deleted" do
    bucket = FakeBucket.new
    bucket.install do
      line = ProductLine.create!(internal_name: "A", customer_name: "제품", slug: "audit-line", introduction: "소개")
      season = line.product_seasons.create!(internal_name: "S", season_code: "S01", slug: "s01")
      episode = season.content_episodes.create!(position: 1, customer_title: "편")
      good = episode.content_assets.create!(title: "정상", kind: "k", position: 1, file: { io: file_fixture("assets/sample.zip").open, filename: "a.zip", content_type: "application/zip" })
      lost = episode.content_assets.create!(title: "유실", kind: "k", position: 2, file: { io: file_fixture("assets/sample.war").open, filename: "b.war", content_type: "application/zip" })
      bad = episode.content_assets.create!(title: "손상", kind: "k", position: 3, file: { io: file_fixture("assets/sample.pdf").open, filename: "c.pdf", content_type: "application/pdf" })

      clean = StorageVerifier.new(service: bucket.service).audit(checksum: true)
      assert_equal 3, clean.blob_count
      assert_empty clean.missing
      assert_empty clean.checksum_mismatch
      assert_empty clean.orphan_objects

      bucket.objects.delete(lost.file.blob.key)
      bucket.objects[bad.file.blob.key] = "corrupted".b
      bucket.objects["leftover/orphan-object"] = "x".b
      bucket.objects["#{StorageVerifier::CHECK_PREFIX}ignored"] = "x".b
      keys_before = bucket.keys.sort

      audit = StorageVerifier.new(service: bucket.service).audit(checksum: true)
      assert_equal [ lost.file.blob.id ], audit.missing.map(&:id)
      assert_equal [ bad.file.blob.id ], audit.checksum_mismatch.map(&:id)
      assert_equal [ "leftover/orphan-object" ], audit.orphan_objects
      assert_includes bucket.keys, good.file.blob.key
      assert_equal keys_before, bucket.keys.sort, "the audit must be read-only"

      without_checksum = StorageVerifier.new(service: bucket.service).audit
      assert_empty without_checksum.checksum_mismatch, "checksums are only verified on request"
    end
  end

  test "audit on the local Disk service ignores unrelated files sharing its folder (SQLite databases etc.)" do
    root = Pathname(ActiveStorage::Blob.service.root)
    FileUtils.mkdir_p(root)
    stray = root.join("production_queue_probe.sqlite3")
    stray.write("not an active storage object")
    audit = StorageVerifier.new.audit
    assert audit.listing_supported
    assert_not_includes audit.orphan_objects, "production_queue_probe.sqlite3"
  ensure
    stray&.delete if stray&.exist?
  end

  test "storage:check prints the service and PASS, and exits non-zero with FAIL when the storage is down" do
    out, status = run_task("storage:check")
    assert_nil status
    assert_match(/RESULT: PASS/, out)
    assert_match(/ActiveStorage::Service::DiskService/, out)

    bucket = FakeBucket.new
    bucket.install do
      out, status = run_task("storage:check")
      assert_nil status
      assert_includes out, "fake-private-bucket"
      assert_match(/RESULT: PASS/, out)

      bucket.outage = Aws::S3::Errors::ServiceUnavailable.new(nil, "down")
      out, status = run_task("storage:check")
      assert_equal 1, status
      assert_match(/RESULT: FAIL/, out)
      assert_no_match(/secret|access_key/i, out)
    end
  end

  test "storage:audit exits non-zero only when a stored file is really missing" do
    bucket = FakeBucket.new
    bucket.install do
      line = ProductLine.create!(internal_name: "A", customer_name: "제품", slug: "audit-line-2", introduction: "소개")
      line.update!(cover_image: { io: file_fixture("covers/cover.jpg").open, filename: "c.jpg", content_type: "image/jpeg" }, cover_image_alt: "x")

      out, status = run_task("storage:audit")
      assert_nil status
      assert_match(/missing files\s+: 0/, out)

      bucket.objects.clear
      out, status = run_task("storage:audit")
      assert_equal 1, status
      assert_match(/missing files\s+: 1/, out)
      assert_match(/c\.jpg/, out)
    end
  end
end
