require "test_helper"

class ContentManifestTest < ActiveSupport::TestCase
  # Uses an isolated Dir.mktmpdir rather than a shared hq/ directory --
  # bin/rails test runs in parallel worker processes, and writing into a
  # directory other tests concurrently read from caused a real ENOENT race
  # elsewhere in this suite (see test/models/claudox_test.rb history).
  test "returns the manifest's timestamp converted to the app's time zone" do
    Dir.mktmpdir do |dir|
      directory = Pathname.new(dir)
      File.write(directory.join(".last_updated.json"), { "01_test.md" => "2026-07-26T12:30:00+09:00" }.to_json)

      result = ContentManifest.last_updated_at(directory, "01_test")

      assert_equal Time.iso8601("2026-07-26T12:30:00+09:00"), result
      assert_equal ActiveSupport::TimeZone["Asia/Seoul"], result.time_zone
    end
  end

  test "converts a non-KST offset in the manifest to the app's time zone for display" do
    Dir.mktmpdir do |dir|
      directory = Pathname.new(dir)
      File.write(directory.join(".last_updated.json"), { "01_test.md" => "2026-07-26T03:30:00Z" }.to_json)

      result = ContentManifest.last_updated_at(directory, "01_test")

      assert_equal ActiveSupport::TimeZone["Asia/Seoul"], result.time_zone
      assert_equal 12, result.hour
    end
  end

  test "falls back to the file's own mtime, zone-converted, when the manifest has no entry for it" do
    Dir.mktmpdir do |dir|
      directory = Pathname.new(dir)
      file = directory.join("02_test.md")
      File.write(file, "content")
      File.write(directory.join(".last_updated.json"), {}.to_json)
      File.utime(Time.now, Time.utc(2026, 1, 1, 3, 0, 0), file)

      result = ContentManifest.last_updated_at(directory, "02_test")

      assert_equal Time.utc(2026, 1, 1, 3, 0, 0), result
      assert_equal ActiveSupport::TimeZone["Asia/Seoul"], result.time_zone
    end
  end

  test "falls back to the file's mtime when there is no manifest file at all" do
    Dir.mktmpdir do |dir|
      directory = Pathname.new(dir)
      file = directory.join("03_test.md")
      File.write(file, "content")

      result = ContentManifest.last_updated_at(directory, "03_test")

      assert_in_delta File.mtime(file).to_f, result.to_f, 2
    end
  end
end
