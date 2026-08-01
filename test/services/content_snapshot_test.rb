require "test_helper"
require_relative "../support/content_snapshot_fixture"

class ContentSnapshotTest < ActiveSupport::TestCase
  include ContentSnapshotFixture

  test "builds published bodies and only referenced images with byte parity" do
    with_source_and_target do |source, target|
      build(source, target)

      assert target.join("s01/S01E01_first.md").file?
      assert_not target.join("s01/S01E02_draft.md").exist?
      assert target.join("s01/images/used.png").file?
      assert target.join("s01/images/nested/diagram.png").file?
      assert_not target.join("s01/images/example-only.png").exist?
      assert_equal source.join("s01/images/used.png").binread, target.join("s01/images/used.png").binread
      assert_equal source.join("s01/S01E01_first.md").binread, target.join("s01/S01E01_first.md").binread
    end
  end

  test "writes deterministic POSIX manifest order and separates build timestamp" do
    Dir.mktmpdir do |directory|
      base = Pathname.new(directory)
      source = base.join("source")
      create_product_tree(source)
      first = base.join("first")
      second = base.join("second")

      build(source, first, generated_at: Time.zone.parse("2026-08-01 10:00:00"))
      build(source, second, generated_at: Time.zone.parse("2026-08-02 10:00:00"))

      assert_equal first.join("manifest.yml").binread, second.join("manifest.yml").binread
      assert_not_equal first.join("build.yml").binread, second.join("build.yml").binread
      manifest = YAML.safe_load(first.join("manifest.yml").read)
      paths = manifest["files"].pluck("path")
      assert_equal paths.sort, paths
      assert paths.none? { |path| path.include?("\\") }
      assert_equal COMMIT, manifest["source_commit"]
      assert_equal [ 1, 1 ], manifest["seasons"].pluck("published_episode_count")
    end
  end

  test "rejects all output on catalog or season validation errors" do
    with_source_and_target do |source, target|
      target.mkpath
      target.join("sentinel.txt").write("old snapshot")
      source.join("s02/S02E01_first.md").delete

      error = assert_raises(ContentSnapshot::Error) { build(source, target) }
      assert_equal :catalog_invalid, error.code
      assert_equal "old snapshot", target.join("sentinel.txt").read
      assert_not target.join("manifest.yml").exist?
    end
  end

  test "rejects referenced image symlink escapes and preserves old target" do
    Dir.mktmpdir do |outside|
      with_source_and_target do |source, target|
        image = source.join("s01/images/used.png")
        image.delete
        Pathname.new(outside).join("outside.png").binwrite("outside")
        File.symlink(Pathname.new(outside).join("outside.png"), image)
        target.mkpath
        target.join("sentinel.txt").write("old")

        error = assert_raises(ContentSnapshot::Error) { build(source, target) }
        assert_equal :image_missing_or_unsafe, error.code
        assert_equal "old", target.join("sentinel.txt").read
      end
    end
  end

  test "requires a full source commit" do
    with_source_and_target do |source, target|
      error = assert_raises(ContentSnapshot::Error) do
        ContentSnapshot::Builder.new(source_root: source, source_commit: "abc123", target:).build!
      end
      assert_equal :invalid_source_commit, error.code
    end
  end

  test "Git source records clean full HEAD and excludes ignored local files" do
    with_git_repository do |repository, target|
      repository.join(".local/handoff/inbox").mkpath
      repository.join(".local/handoff/inbox/request.md").write("ignored")
      expected_commit = git_output(repository, "rev-parse", "HEAD").strip

      ContentSnapshot::BuildFromGit.call(
        repository_root: repository,
        source_path: "hq/chatdox",
        target:,
        generated_at: Time.zone.parse("2026-08-01 10:00:00")
      )

      manifest = YAML.safe_load(target.join("manifest.yml").read)
      assert_equal expected_commit, manifest["source_commit"]
      assert_equal 40, manifest["source_commit"].length
      assert_not target.join(".local").exist?
    end
  end

  test "Git source rejects dirty tracked and untracked files" do
    with_git_repository do |repository, target|
      repository.join("README.md").write("dirty")
      assert_git_error(:dirty_worktree, repository, target)
    end

    with_git_repository do |repository, target|
      repository.join("hq/chatdox/untracked.md").write("untracked")
      assert_git_error(:dirty_worktree, repository, target)
    end
  end

  test "Git source rejects detached HEAD" do
    with_git_repository do |repository, target|
      run_git(repository, "checkout", "--detach", "-q")
      assert_git_error(:detached_head, repository, target)
    end
  end

  test "Git source rejects an empty or escaping source path" do
    with_git_repository do |repository, _target|
      [ "", "../chatdox", "hq\\chatdox" ].each do |source_path|
        error = assert_raises(ContentSnapshot::Error) do
          ContentSnapshot::GitSource.new(repository_root: repository, source_path:).with_committed_tree { flunk }
        end
        assert_equal :unsafe_git_source_path, error.code
      end
    end
  end

  test "Git source rejects shallow clones" do
    Dir.mktmpdir do |directory|
      base = Pathname.new(directory)
      original = base.join("original")
      init_git_repository(original)
      original.join("README.md").write("second")
      run_git(original, "add", ".")
      run_git(original, "commit", "-qm", "second")
      shallow = base.join("shallow")
      system("git", "clone", "-q", "--depth", "1", "file://#{original}", shallow.to_s, exception: true)

      assert_git_error(:shallow_repository, shallow, base.join("target"))
    end
  end

  test "failed committed-tree validation never replaces an existing snapshot" do
    with_git_repository do |repository, target|
      target.mkpath
      target.join("sentinel.txt").write("old")
      repository.join("hq/chatdox/catalog.yml").write("broken: [")
      run_git(repository, "add", ".")
      run_git(repository, "commit", "-qm", "broken catalog")

      assert_raises(ContentSnapshot::Error) do
        ContentSnapshot::BuildFromGit.call(repository_root: repository, source_path: "hq/chatdox", target:)
      end
      assert_equal "old", target.join("sentinel.txt").read
    end
  end

  private

  COMMIT = "a" * 40

  def with_source_and_target
    Dir.mktmpdir do |directory|
      base = Pathname.new(directory)
      source = base.join("source")
      create_product_tree(source)
      yield source, base.join("runtime")
    end
  end

  def with_git_repository
    Dir.mktmpdir do |directory|
      base = Pathname.new(directory)
      repository = base.join("repository")
      init_git_repository(repository)
      yield repository, base.join("runtime")
    end
  end

  def build(source, target, generated_at: Time.zone.parse("2026-08-01 10:00:00"))
    ContentSnapshot::Builder.new(
      source_root: source,
      source_commit: COMMIT,
      target:,
      generated_at:
    ).build!
  end

  def assert_git_error(code, repository, target)
    error = assert_raises(ContentSnapshot::Error) do
      ContentSnapshot::BuildFromGit.call(repository_root: repository, source_path: "hq/chatdox", target:)
    end
    assert_equal code, error.code
  end

  def git_output(repository, *arguments)
    IO.popen([ "git", "-C", repository.to_s, *arguments ], &:read)
  end
end
