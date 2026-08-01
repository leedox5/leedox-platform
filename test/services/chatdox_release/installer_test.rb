require "test_helper"
require_relative "../../support/content_snapshot_fixture"

class ChatdoxRelease::InstallerTest < ActiveSupport::TestCase
  include ContentSnapshotFixture

  test "requires confirmation and preserves current target" do
    with_artifact do |artifact, target|
      target.mkpath
      target.join("sentinel").write("current")

      error = assert_raises(ContentSnapshot::Error) do
        ChatdoxRelease::Installer.call(artifact:, target:, expected_commit: COMMIT, confirm: false)
      end

      assert_equal :confirmation_required, error.code
      assert_equal "current", target.join("sentinel").read
    end
  end

  test "atomically installs verified artifact and is idempotent" do
    with_artifact do |artifact, target|
      first = ChatdoxRelease::Installer.call(artifact:, target:, expected_commit: COMMIT, confirm: true)
      second = ChatdoxRelease::Installer.call(artifact:, target:, expected_commit: COMMIT, confirm: true)

      assert_equal :installed, first.status
      assert_equal :unchanged, second.status
      assert ProductContent::RuntimeSnapshotVerifier.verify(root: target, expected_source_commit: COMMIT).usable?
    end
  end

  test "rejects checksum mismatch without replacing current target" do
    with_artifact do |artifact, target|
      target.mkpath
      target.join("sentinel").write("current")
      artifact.join("s01/S01E01_first.md").write("tampered")

      error = assert_raises(ContentSnapshot::Error) do
        ChatdoxRelease::Installer.call(artifact:, target:, expected_commit: COMMIT, confirm: true)
      end

      assert_equal :artifact_invalid, error.code
      assert_equal "current", target.join("sentinel").read
    end
  end

  private

  COMMIT = "e" * 40

  def with_artifact
    Dir.mktmpdir do |directory|
      base = Pathname.new(directory)
      source = base.join("source")
      create_product_tree(source)
      artifact = base.join("artifact")
      ContentSnapshot::Builder.new(source_root: source, source_commit: COMMIT, target: artifact).build!
      yield artifact, base.join("installed")
    end
  end
end
