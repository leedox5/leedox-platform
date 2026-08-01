require "test_helper"
require_relative "../../support/content_snapshot_fixture"

class ChatdoxRelease::ReadinessTest < ActiveSupport::TestCase
  include ContentSnapshotFixture

  setup do
    @directory = Dir.mktmpdir
    @previous = %w[CHATDOX_CONTENT_SOURCE CHATDOX_SNAPSHOT_PATH CHATDOX_EXPECTED_SOURCE_COMMIT]
      .to_h { |key| [ key, ENV[key] ] }
  end

  teardown do
    @previous.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
    FileUtils.remove_entry(@directory)
  end

  test "reports not configured without touching a snapshot" do
    ENV["CHATDOX_CONTENT_SOURCE"] = "legacy"

    result = ChatdoxRelease::Readiness.call

    assert_equal :not_configured, result.state
    assert_equal :source_not_configured, result.reason
    assert_not result.canonical_routes
  end

  test "reports redacted ready public catalog" do
    snapshot = build_snapshot
    configure(snapshot)

    result = ChatdoxRelease::Readiness.call

    assert_equal :ready, result.state
    assert_equal :ready, result.reason
    assert_equal COMMIT.first(12), result.installed_commit
    assert_equal [ [ "s01", 1 ], [ "s02", 0 ] ], result.seasons.map { |season| [ season[:code], season[:public_episode_count] ] }
    assert_empty result.diagnostics
    assert_not_includes result.to_h.to_s, snapshot.to_s
  end

  test "maps checksum failure to stable blocked reason without path or full checksum" do
    snapshot = build_snapshot
    snapshot.join("s01/S01E01_first.md").write("tampered")
    configure(snapshot)

    result = ChatdoxRelease::Readiness.call

    assert_equal :blocked, result.state
    assert_equal :checksum_mismatch, result.reason
    assert_equal [ { severity: :error, code: :checksum_mismatch, count: 1 } ], result.diagnostics
    assert_not_includes result.to_h.to_s, snapshot.to_s
  end

  private

  COMMIT = "d" * 40

  def build_snapshot
    base = Pathname.new(@directory)
    source = base.join("source")
    create_product_tree(source, s02_status: "review")
    target = base.join("runtime")
    ContentSnapshot::Builder.new(source_root: source, source_commit: COMMIT, target:).build!
    target
  end

  def configure(snapshot)
    ENV["CHATDOX_CONTENT_SOURCE"] = "seasoned"
    ENV["CHATDOX_SNAPSHOT_PATH"] = snapshot.to_s
    ENV["CHATDOX_EXPECTED_SOURCE_COMMIT"] = COMMIT
  end
end
