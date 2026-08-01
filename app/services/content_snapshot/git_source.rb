require "open3"

module ContentSnapshot
  class GitSource
    def initialize(repository_root:, source_path:)
      @repository_root = Pathname.new(repository_root).expand_path
      @source_path = source_path.to_s
    end

    def with_committed_tree
      validate_source_path!
      validate_repository!
      commit = git!("rev-parse", "HEAD").strip

      Dir.mktmpdir("content-snapshot-source-") do |directory|
        archive = git_binary!("archive", "--format=tar", "#{commit}:#{@source_path}")
        extract_archive!(archive, directory)
        yield Pathname.new(directory), commit
      end
    end

    private

    def validate_source_path!
      path = Pathname.new(@source_path)
      safe = @source_path.present? && !path.absolute? &&
        path.each_filename.none? { |part| part == ".." } && !@source_path.include?("\\")
      return if safe

      raise Error.new(:unsafe_git_source_path, "Git source path must be a safe repository-relative path")
    end

    def validate_repository!
      raise Error.new(:git_repository_missing, "Git repository root is missing") unless @repository_root.directory?
      raise Error.new(:detached_head, "Snapshot source must be on a branch") unless git_success?("symbolic-ref", "-q", "HEAD")
      raise Error.new(:shallow_repository, "Snapshot source repository must not be shallow") if git!("rev-parse", "--is-shallow-repository").strip == "true"
      raise Error.new(:dirty_worktree, "Snapshot source repository must have a clean working tree") if git!("status", "--porcelain", "--untracked-files=all").present?
      raise Error.new(:source_commit_missing, "HEAD commit object is unavailable") unless git_success?("cat-file", "-e", "HEAD^{commit}")
      raise Error.new(:git_source_missing, "Git source tree #{@source_path} does not exist at HEAD") unless git_success?("cat-file", "-e", "HEAD:#{@source_path}")
    end

    def extract_archive!(archive, directory)
      _stdout, stderr, status = Open3.capture3("tar", "-xf", "-", "-C", directory, stdin_data: archive, binmode: true)
      return if status.success?

      raise Error.new(:git_archive_extract_failed, "Could not extract committed content tree: #{stderr.lines.first&.strip}")
    end

    def git!(*arguments)
      stdout, stderr, status = Open3.capture3("git", "-C", @repository_root.to_s, *arguments)
      return stdout if status.success?

      raise Error.new(:git_command_failed, "Git command failed: #{stderr.lines.first&.strip}")
    end

    def git_binary!(*arguments)
      stdout, stderr, status = Open3.capture3("git", "-C", @repository_root.to_s, *arguments, binmode: true)
      return stdout if status.success?

      raise Error.new(:git_archive_failed, "Could not archive committed content tree: #{stderr.lines.first&.strip}")
    end

    def git_success?(*arguments)
      _stdout, _stderr, status = Open3.capture3("git", "-C", @repository_root.to_s, *arguments)
      status.success?
    end
  end
end
