require "fileutils"

module ChatdoxRelease
  class Installer
    Result = Data.define(:status, :source_commit, :previous_commit)

    def self.call(artifact:, target:, expected_commit:, confirm: false)
      new(artifact:, target:, expected_commit:, confirm:).call
    end

    def initialize(artifact:, target:, expected_commit:, confirm:)
      @artifact = Pathname.new(artifact).expand_path
      @target = Pathname.new(target).expand_path
      @expected_commit = expected_commit.to_s
      @confirm = confirm
    end

    def call
      raise ContentSnapshot::Error.new(:confirmation_required, "Install requires CONFIRM_PRODUCTION=1") unless @confirm

      source = verified(@artifact)
      raise ContentSnapshot::Error.new(:source_commit_mismatch, "Artifact does not match approved commit") unless source.source_commit == @expected_commit

      @target.dirname.mkpath
      File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        raise ContentSnapshot::Error.new(:release_locked, "Another release owns the install target") unless lock.flock(File::LOCK_EX | File::LOCK_NB)

        install(source)
      end
    end

    private

    def verified(path)
      snapshot = ProductContent::RuntimeSnapshotVerifier.verify(root: path, expected_source_commit: @expected_commit)
      return snapshot if snapshot.usable?

      raise ContentSnapshot::Error.new(:artifact_invalid, "Artifact validation failed")
    end

    def install(source)
      current = @target.exist? ? ProductContent::RuntimeSnapshotVerifier.verify(root: @target) : nil
      return Result.new(status: :unchanged, source_commit: source.source_commit, previous_commit: current&.source_commit) if current&.usable? && current.source_commit == source.source_commit

      staging = Pathname.new(Dir.mktmpdir(".#{@target.basename}.install-", @target.dirname.to_s))
      backup = @target.dirname.join(".#{@target.basename}.previous")
      FileUtils.copy_entry(@artifact, staging, false, false, true)
      verified(staging)
      FileUtils.rm_rf(backup)
      File.rename(@target, backup) if @target.exist?
      File.rename(staging, @target)
      verified(@target)
      Result.new(status: :installed, source_commit: source.source_commit, previous_commit: current&.source_commit)
    rescue StandardError
      FileUtils.rm_rf(@target) if backup.exist? && @target.exist?
      File.rename(backup, @target) if backup.exist? && !@target.exist?
      raise
    ensure
      FileUtils.rm_rf(staging) if staging&.exist?
    end

    def lock_path
      @target.dirname.join(".#{@target.basename}.release.lock")
    end
  end
end
