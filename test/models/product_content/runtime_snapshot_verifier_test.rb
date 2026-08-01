require "test_helper"
require_relative "../../support/content_snapshot_fixture"

class ProductContent::RuntimeSnapshotVerifierTest < ActiveSupport::TestCase
  include ContentSnapshotFixture

  test "accepts a complete snapshot and exposes its source commit" do
    with_snapshot do |root|
      snapshot = verify(root)

      assert snapshot.usable?
      assert_equal COMMIT, snapshot.source_commit
      assert_equal %w[s01 s02], snapshot.catalog.seasons.pluck(:code)
      assert_empty snapshot.diagnostics
    end
  end

  test "rejects manifest and build commit problems" do
    with_snapshot do |root|
      update_yaml(root.join("build.yml")) { |data| data["source_commit"] = "b" * 40 }
      assert_code(root, :snapshot_commit_mismatch)
    end

    with_snapshot do |root|
      update_yaml(root.join("manifest.yml")) { |data| data["source_commit"] = "short" }
      assert_code(root, :invalid_manifest_source_commit)
    end
  end

  test "rejects a valid snapshot from a different configured release" do
    with_snapshot do |root|
      snapshot = ProductContent::RuntimeSnapshotVerifier.verify(root:, expected_source_commit: "b" * 40)

      assert_not snapshot.usable?
      assert_includes snapshot.diagnostics.pluck(:code), :unexpected_snapshot_source_commit
    end
  end

  test "rejects checksum mismatch missing and extra payload" do
    with_snapshot do |root|
      root.join("s01/S01E01_first.md").write("tampered")
      assert_code(root, :snapshot_checksum_mismatch)
    end

    with_snapshot do |root|
      root.join("s01/S01E01_first.md").delete
      assert_code(root, :snapshot_file_missing_or_unsafe)
    end

    with_snapshot do |root|
      root.join("s01/extra.md").write("extra")
      assert_code(root, :unmanifested_snapshot_file)
    end
  end

  test "rejects traversal visibility mismatch and symlink payload" do
    with_snapshot do |root|
      update_yaml(root.join("manifest.yml")) do |data|
        data["files"] << { "path" => "../secret", "sha256" => "0" * 64, "visibility" => "public" }
      end
      assert_code(root, :unsafe_manifest_path)
    end

    with_snapshot do |root|
      update_yaml(root.join("manifest.yml")) { |data| data["files"].first["visibility"] = "protected_archived" }
      assert_code(root, :manifest_visibility_path_mismatch)
    end

    Dir.mktmpdir do |outside|
      with_snapshot do |root|
        file = root.join("s01/S01E01_first.md")
        file.delete
        Pathname.new(outside).join("body.md").write("outside")
        File.symlink(Pathname.new(outside).join("body.md"), file)
        assert_code(root, :snapshot_file_missing_or_unsafe)
      end
    end
  end

  test "propagates catalog diagnostics and rejects season summary drift" do
    with_snapshot do |root|
      metadata = YAML.safe_load(root.join("s02/content_meta.yml").read)
      metadata["season"]["status"] = "live"
      root.join("s02/content_meta.yml").write(metadata.to_yaml)
      assert_code(root, :unknown_season_status)
    end

    with_snapshot do |root|
      update_yaml(root.join("manifest.yml")) { |data| data["seasons"][0]["published_episode_count"] = 99 }
      assert_code(root, :snapshot_season_summary_mismatch)
    end
  end

  test "warns and hides published episodes in an upcoming season without invalidating integrity" do
    with_snapshot(s02_status: "published") do |root|
      snapshot = verify(root)

      assert snapshot.usable?
      assert_includes snapshot.diagnostics.pluck(:code), :published_in_nonpublic_season
    end
  end

  private

  COMMIT = "a" * 40

  def with_snapshot(s02_status: "review")
    Dir.mktmpdir do |directory|
      base = Pathname.new(directory)
      source = base.join("source")
      create_product_tree(source, s02_status:)
      target = base.join("runtime")
      ContentSnapshot::Builder.new(source_root: source, source_commit: COMMIT, target:).build!
      yield target
    end
  end

  def verify(root)
    ProductContent::RuntimeSnapshotVerifier.verify(root:)
  end

  def assert_code(root, code)
    snapshot = verify(root)
    assert_not snapshot.usable?
    assert_includes snapshot.diagnostics.pluck(:code), code
  end

  def update_yaml(path)
    data = YAML.safe_load(path.read)
    yield data
    path.write(data.to_yaml)
  end
end
