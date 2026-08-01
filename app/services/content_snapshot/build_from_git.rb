module ContentSnapshot
  class BuildFromGit
    def self.call(repository_root:, source_path:, target:, product_code: "chatdox", generated_at: Time.current)
      GitSource.new(repository_root:, source_path:).with_committed_tree do |source_root, commit|
        Builder.new(source_root:, source_commit: commit, target:, product_code:, generated_at:).build!
      end
    end
  end
end
