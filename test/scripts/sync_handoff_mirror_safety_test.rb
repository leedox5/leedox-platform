require "test_helper"
require "fileutils"
require "open3"
require "tmpdir"

# Regression coverage for leedox_sync_handoff_mirror_safety_r1: a real
# (non-dry-run) `--mirror` used to delete local files based purely on
# whatever a *separate*, earlier `--dry-run` call happened to preview --
# which can drift from what the real run actually deletes. The fix makes
# `--mirror` compute its own delete preview and require confirmation (or
# `--yes`) inside the same invocation that performs the deletion.
class SyncHandoffMirrorSafetyTest < ActiveSupport::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("sync-handoff-safety-test")
    @project = File.join(@tmpdir, "project")
    @hq = File.join(@tmpdir, "hq")

    FileUtils.mkdir_p(@project)
    FileUtils.cp_r(Rails.root.join("script"), @project)
    FileUtils.mkdir_p(File.join(@hq, ".local/handoff/inbox"))
    File.write(File.join(@hq, ".local/handoff/inbox/request.md"), "request\n")
  end

  teardown do
    FileUtils.rm_rf(@tmpdir)
  end

  test "plain --dry-run (no --mirror) never previews or performs deletions" do
    stale_file = create_stale_local_file

    output, status = run_script("--dry-run")

    assert_predicate status, :success?, output
    assert_not_includes output, "will be deleted"
    assert File.exist?(stale_file)
  end

  test "--mirror --dry-run previews deletions without touching the target" do
    stale_file = create_stale_local_file

    output, status = run_script("--dry-run", "--mirror")

    assert_predicate status, :success?, output
    assert_includes output, "*deleting"
    assert_includes output, "outbox/stale-package/result.md"
    assert File.exist?(stale_file), "dry-run must not actually delete anything"
  end

  test "real --mirror without --yes aborts without deleting when input is not confirmed" do
    stale_file = create_stale_local_file

    output, status = run_script("--mirror", stdin_data: "n\n")

    assert_not_predicate status, :success?
    assert_includes output, "will be deleted"
    assert_includes output, "Re-run with --yes"
    assert File.exist?(stale_file), "declining the prompt must leave local files untouched"
  end

  test "real --mirror without --yes aborts when there is no interactive input at all" do
    stale_file = create_stale_local_file

    output, status = run_script("--mirror", stdin_data: "")

    assert_not_predicate status, :success?
    assert File.exist?(stale_file), "non-interactive runs must fail safe, not delete"
  end

  test "real --mirror with --yes deletes without prompting" do
    stale_file = create_stale_local_file

    output, status = run_script("--mirror", "--yes")

    assert_predicate status, :success?, output
    assert_not_includes output, "Proceed with deletion?"
    assert_not File.exist?(stale_file)
  end

  test "real --mirror proceeds when the user confirms interactively" do
    stale_file = create_stale_local_file

    output, status = run_script("--mirror", stdin_data: "y\n")

    assert_predicate status, :success?, output
    assert_not File.exist?(stale_file)
  end

  test "--mirror with nothing to delete does not prompt" do
    output, status = run_script("--mirror")

    assert_predicate status, :success?, output
    assert_not_includes output, "will be deleted"
    assert_not_includes output, "Proceed with deletion?"
  end

  private

  # Simulates the exact scenario from the original incident: a package that
  # exists locally (e.g. in outbox/) but not on the HQ side, so a --mirror
  # sync would delete it.
  def create_stale_local_file
    target = File.join(@project, ".local/handoff")
    package_dir = File.join(target, "outbox/stale-package")
    FileUtils.mkdir_p(package_dir)
    stale_file = File.join(package_dir, "result.md")
    File.write(stale_file, "stale\n")
    stale_file
  end

  def run_script(*args, stdin_data: nil)
    env = { "PATH" => ENV.fetch("PATH"), "HOME" => @tmpdir, "HQ_DIR" => @hq }
    opts = { chdir: @project, unsetenv_others: true }
    opts[:stdin_data] = stdin_data unless stdin_data.nil?

    stdout, stderr, status = Open3.capture3(
      env,
      File.join(@project, "script/sync_handoff.sh"),
      *args,
      **opts
    )
    [ stdout + stderr, status ]
  end
end
