require "test_helper"
require "digest"
require "fileutils"
require "open3"
require "tmpdir"

class HqSyncScriptsTest < ActiveSupport::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("hq-sync-test")
    @project = File.join(@tmpdir, "project")
    @handoff_hq = File.join(@tmpdir, "handoff-hq")
    @legacy_hq = File.join(@tmpdir, "legacy-hq")
    @curriculum_hq = File.join(@tmpdir, "curriculum-hq")

    FileUtils.mkdir_p(@project)
    FileUtils.cp_r(Rails.root.join("script"), @project)
    create_handoff_hq(@handoff_hq)
    create_handoff_hq(@legacy_hq)
    create_curriculum_repo(@curriculum_hq)
  end

  teardown do
    FileUtils.rm_rf(@tmpdir)
  end

  test "namespaced handoff variable wins over legacy fallbacks" do
    output, status = run_script(
      "sync_handoff.sh", "--dry-run",
      env: { "HANDOFF_HQ_DIR" => @handoff_hq, "HQ_DIR" => @legacy_hq, "SOURCE_REPO" => @legacy_hq }
    )

    assert_predicate status, :success?, output
    assert_includes output, "Source: #{File.realpath(@handoff_hq)}/.local/handoff"
    assert_includes output, "Selected by: HANDOFF_HQ_DIR"
  end

  test "direct source override wins over namespaced handoff variable" do
    direct_hq = File.join(@tmpdir, "direct-hq")
    create_handoff_hq(direct_hq)

    output, status = run_script(
      "sync_handoff.sh", "--dry-run",
      env: {
        "SOURCE_DIR" => File.join(direct_hq, ".local/handoff"),
        "HANDOFF_HQ_DIR" => @handoff_hq
      }
    )

    assert_predicate status, :success?, output
    assert_includes output, "Source: #{File.realpath(direct_hq)}/.local/handoff"
    assert_includes output, "Selected by: SOURCE_DIR"
  end

  test "legacy HQ_DIR fallback keeps working and emits a notice" do
    output, status = run_script("sync_handoff.sh", "--dry-run", env: { "HQ_DIR" => @legacy_hq })

    assert_predicate status, :success?, output
    assert_includes output, "Selected by: HQ_DIR"
    assert_includes output, "HQ_DIR is a legacy fallback"
  end

  test "legacy SOURCE_REPO fallback keeps working for handoff and curriculum" do
    pull_output, pull_status = run_script(
      "sync_handoff.sh", "--dry-run",
      env: { "SOURCE_REPO" => @legacy_hq }
    )
    curriculum_output, curriculum_status = run_script(
      "sync_curriculum.sh", "--dry-run",
      env: { "SOURCE_REPO" => @curriculum_hq }
    )

    assert_predicate pull_status, :success?, pull_output
    assert_includes pull_output, "Selected by: SOURCE_REPO"
    assert_predicate curriculum_status, :success?, curriculum_output
    assert_includes curriculum_output, "Selected by: SOURCE_REPO"
  end

  test "project dotenv can select the namespaced handoff HQ" do
    File.write(File.join(@project, ".env"), "HANDOFF_HQ_DIR=#{@handoff_hq}\n")

    output, status = run_script("sync_handoff.sh", "--dry-run")

    assert_predicate status, :success?, output
    assert_includes output, "Source: #{File.realpath(@handoff_hq)}/.local/handoff"
    assert_includes output, "Selected by: HANDOFF_HQ_DIR"
  end

  test "explicit environment wins over project dotenv values" do
    File.write(File.join(@project, ".env"), "HANDOFF_HQ_DIR=#{@legacy_hq}\n")

    output, status = run_script(
      "sync_handoff.sh", "--dry-run",
      env: { "HANDOFF_HQ_DIR" => @handoff_hq }
    )

    assert_predicate status, :success?, output
    assert_includes output, "Source: #{File.realpath(@handoff_hq)}/.local/handoff"
  end

  test "handoff and curriculum namespaced variables remain independent" do
    pull_output, pull_status = run_script(
      "sync_handoff.sh", "--dry-run",
      env: { "HANDOFF_HQ_DIR" => @handoff_hq, "CURRICULUM_HQ_DIR" => @curriculum_hq }
    )
    curriculum_output, curriculum_status = run_script(
      "sync_curriculum.sh", "--dry-run",
      env: { "HANDOFF_HQ_DIR" => @handoff_hq, "CURRICULUM_HQ_DIR" => @curriculum_hq }
    )

    assert_predicate pull_status, :success?, pull_output
    assert_includes pull_output, "Source: #{File.realpath(@handoff_hq)}/.local/handoff"
    assert_predicate curriculum_status, :success?, curriculum_output
    assert_includes curriculum_output, "Source: #{File.realpath(@curriculum_hq)}"
    assert_includes curriculum_output, "Selected by: CURRICULUM_HQ_DIR"
  end

  test "handoff pull dry run leaves an existing target tree unchanged" do
    target = File.join(@project, ".local/handoff")
    FileUtils.mkdir_p(File.join(target, "outbox/local-only"))
    File.binwrite(File.join(target, "outbox/local-only/result.md"), "local\n")
    before = tree_snapshot(target)

    output, status = run_script(
      "sync_handoff.sh", "--dry-run", "--mirror",
      env: { "HANDOFF_HQ_DIR" => @handoff_hq }
    )

    assert_predicate status, :success?, output
    assert_equal before, tree_snapshot(target)
  end

  test "push dry run does not create the package target" do
    package = create_outbox_package("dry-run-package", "result\n")
    package_target = File.join(@handoff_hq, ".local/handoff/inbox/dry-run-package")

    output, status = run_script(
      "push_handoff_to_curriculum.sh", "--source", package, "--dry-run",
      env: { "HANDOFF_HQ_DIR" => @handoff_hq }
    )

    assert_predicate status, :success?, output
    assert_not File.exist?(package_target)
  end

  test "push continues to reject the outbox root" do
    outbox = File.join(@project, ".local/handoff/outbox")
    FileUtils.mkdir_p(outbox)

    output, status = run_script(
      "push_handoff_to_curriculum.sh", "--source", outbox, "--dry-run",
      env: { "HANDOFF_HQ_DIR" => @handoff_hq }
    )

    assert_not_predicate status, :success?
    assert_includes output, "--source resolves to the outbox root"
  end

  test "single package push preserves UTF-8 CRLF bytes" do
    content = "# 결과\r\n\r\n안녕하세요, Tommy.\r\n".b
    package = create_outbox_package("utf8-crlf", content)

    output, status = run_script(
      "push_handoff_to_curriculum.sh", "--source", package,
      env: { "HANDOFF_HQ_DIR" => @handoff_hq }
    )
    pushed = File.join(@handoff_hq, ".local/handoff/inbox/utf8-crlf/result.md")

    assert_predicate status, :success?, output
    assert_equal content, File.binread(pushed)
  end

  test "mirror warns about protected paths and deletes source-missing files" do
    target = File.join(@project, ".local/handoff")
    %w[outbox completed shared].each do |directory|
      FileUtils.mkdir_p(File.join(target, directory))
      File.write(File.join(target, directory, "stale.md"), "stale\n")
    end
    File.write(File.join(target, "stale.md"), "stale\n")

    preview, preview_status = run_script(
      "sync_handoff.sh", "--dry-run", "--mirror",
      env: { "HANDOFF_HQ_DIR" => @handoff_hq }
    )

    assert_predicate preview_status, :success?, preview
    assert_includes preview, "WARNING: mirror will delete protected"
    %w[outbox completed shared].each { |directory| assert_match(/- #{directory}\//, preview) }

    output, status = run_script(
      "sync_handoff.sh", "--mirror",
      env: { "HANDOFF_HQ_DIR" => @handoff_hq }
    )

    assert_predicate status, :success?, output
    assert_not File.exist?(File.join(target, "stale.md"))
    %w[outbox completed shared].each { |directory| assert_not File.exist?(File.join(target, directory)) }
  end

  test "invalid handoff source structure fails before creating a target" do
    invalid_source = File.join(@tmpdir, "not-a-handoff")
    FileUtils.mkdir_p(invalid_source)
    target = File.join(@project, ".local/handoff")

    output, status = run_script(
      "sync_handoff.sh", "--dry-run",
      env: { "SOURCE_DIR" => invalid_source }
    )

    assert_not_predicate status, :success?
    assert_includes output, "Expected a path ending in /.local/handoff"
    assert_not File.exist?(target)
  end

  test "curriculum dry run creates neither runtime target nor manifest" do
    target = File.join(@project, "hq")

    output, status = run_script(
      "sync_curriculum.sh", "--dry-run",
      env: { "CURRICULUM_HQ_DIR" => @curriculum_hq, "HANDOFF_HQ_DIR" => @handoff_hq }
    )

    assert_predicate status, :success?, output
    assert_not File.exist?(target)
    assert_not Dir.glob(File.join(@project, "**/.last_updated.json"), File::FNM_DOTMATCH).any?
  end

  private

  def create_handoff_hq(root)
    FileUtils.mkdir_p(File.join(root, ".local/handoff/inbox"))
    File.write(File.join(root, ".local/handoff/inbox/request.md"), "request\n")
  end

  def create_curriculum_repo(root)
    FileUtils.mkdir_p(File.join(root, "docs"))
    File.write(File.join(root, "docs/01_test.md"), "# Test\n")
    run_command("git", "init", "-b", "main", root)
    run_command("git", "-C", root, "config", "user.email", "test@example.com")
    run_command("git", "-C", root, "config", "user.name", "Test")
    run_command("git", "-C", root, "add", ".")
    run_command("git", "-C", root, "commit", "-m", "fixture")
  end

  def create_outbox_package(name, content)
    package = File.join(@project, ".local/handoff/outbox", name)
    FileUtils.mkdir_p(package)
    File.binwrite(File.join(package, "result.md"), content)
    package
  end

  def run_script(name, *args, env: {})
    stdout, stderr, status = Open3.capture3(
      { "PATH" => ENV.fetch("PATH"), "HOME" => @tmpdir }.merge(env),
      File.join(@project, "script", name),
      *args,
      chdir: @project,
      unsetenv_others: true
    )
    [ stdout + stderr, status ]
  end

  def run_command(*command)
    stdout, stderr, status = Open3.capture3(*command, unsetenv_others: false)
    assert_predicate status, :success?, stdout + stderr
  end

  def tree_snapshot(root)
    return [] unless File.exist?(root)

    Dir.glob(File.join(root, "**/*"), File::FNM_DOTMATCH).filter_map do |path|
      next if [ ".", ".." ].include?(File.basename(path))

      stat = File.lstat(path)
      relative_path = path.delete_prefix("#{root}/")
      digest = stat.file? ? Digest::SHA256.file(path).hexdigest : nil
      [ relative_path, stat.ftype, stat.mode, stat.size, stat.mtime.to_f, digest ]
    end.sort
  end
end
