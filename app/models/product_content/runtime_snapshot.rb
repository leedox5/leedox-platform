class ProductContent::RuntimeSnapshot
  attr_reader :root, :manifest, :build_metadata, :catalog, :diagnostics

  def initialize(root:, manifest:, build_metadata:, catalog:, diagnostics:)
    @root = root
    @manifest = manifest&.freeze
    @build_metadata = build_metadata&.freeze
    @catalog = catalog
    @diagnostics = diagnostics.freeze
  end

  def usable?
    diagnostics.none? { |diagnostic| diagnostic.severity == :error }
  end

  def source_commit
    manifest&.fetch("source_commit", nil)
  end
end
