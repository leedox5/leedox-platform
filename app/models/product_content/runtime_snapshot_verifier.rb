require "digest"

class ProductContent::RuntimeSnapshotVerifier
  SCHEMA_VERSION = 1
  SHA = /\A[0-9a-f]{40}\z/
  CHECKSUM = /\A[0-9a-f]{64}\z/
  CONTROL_FILES = %w[manifest.yml build.yml].freeze

  def self.verify(root:, expected_source_commit: nil)
    new(root:, expected_source_commit:).verify
  end

  def initialize(root:, expected_source_commit:)
    @root = Pathname.new(root).expand_path
    @expected_source_commit = expected_source_commit.presence
    @diagnostics = []
  end

  def verify
    manifest = safe_yaml("manifest.yml", :manifest)
    build = safe_yaml("build.yml", :build)
    validate_headers(manifest, build)
    validate_files(manifest)
    catalog = ProductContent::CatalogMetadataLoader.load(root: @root)
    append_catalog_diagnostics(catalog)
    validate_season_summary(manifest, catalog)
    warn_nonpublic_published(catalog)

    ProductContent::RuntimeSnapshot.new(
      root: @root,
      manifest:,
      build_metadata: build,
      catalog:,
      diagnostics: @diagnostics
    )
  rescue Errno::ENOENT, Errno::EACCES => error
    failure(:snapshot_unreadable, "root", "Runtime snapshot is unavailable: #{error.class.name}")
  end

  private

  def safe_yaml(filename, kind)
    value = YAML.safe_load(@root.join(filename).read, aliases: false)
    unless value.is_a?(Hash)
      error(:invalid_snapshot_document, filename, "#{kind.to_s.capitalize} must be a mapping")
      return {}
    end
    value
  rescue Errno::ENOENT
    error(:snapshot_control_file_missing, filename, "Snapshot #{kind} file is missing")
    {}
  rescue Psych::Exception => error
    self.error(:snapshot_yaml_error, filename, "Snapshot #{kind} YAML is invalid: #{error.class.name}")
    {}
  end

  def validate_headers(manifest, build)
    error(:invalid_manifest_schema, "manifest.yml.schema_version", "Manifest schema version must be 1") unless manifest["schema_version"] == SCHEMA_VERSION
    error(:invalid_build_schema, "build.yml.schema_version", "Build schema version must be 1") unless build["schema_version"] == SCHEMA_VERSION
    commit = manifest["source_commit"]
    error(:invalid_manifest_source_commit, "manifest.yml.source_commit", "Manifest source commit must be a full SHA") unless commit.is_a?(String) && SHA.match?(commit)
    error(:snapshot_commit_mismatch, "build.yml.source_commit", "Manifest and build source commits must match") unless build["source_commit"] == commit
    if @expected_source_commit && commit != @expected_source_commit
      error(:unexpected_snapshot_source_commit, "manifest.yml.source_commit", "Snapshot source commit does not match the configured release")
    end
    error(:unexpected_snapshot_product, "manifest.yml.product_code", "Snapshot product must be chatdox") unless manifest["product_code"] == "chatdox"
  end

  def validate_files(manifest)
    entries = manifest["files"]
    unless entries.is_a?(Array)
      error(:invalid_manifest_files, "manifest.yml.files", "Manifest files must be a list")
      return
    end

    paths = []
    entries.each_with_index do |entry, index|
      location = "manifest.yml.files[#{index}]"
      unless entry.is_a?(Hash)
        error(:invalid_manifest_file, location, "Manifest file entry must be a mapping")
        next
      end
      relative = entry["path"]
      checksum = entry["sha256"]
      visibility = entry["visibility"]
      unless safe_relative_file?(relative)
        error(:unsafe_manifest_path, "#{location}.path", "Manifest path must be a safe POSIX relative path")
        next
      end
      paths << relative
      unless %w[public protected_archived].include?(visibility)
        error(:invalid_manifest_visibility, "#{location}.visibility", "Manifest visibility is invalid")
      end
      protected_path = relative.start_with?("protected/archived/")
      if protected_path != (visibility == "protected_archived")
        error(:manifest_visibility_path_mismatch, "#{location}.visibility", "Manifest visibility does not match its path")
      end
      error(:invalid_manifest_checksum, "#{location}.sha256", "Manifest checksum must be SHA-256") unless checksum.is_a?(String) && CHECKSUM.match?(checksum)
      verify_file(relative, checksum, location) if checksum.is_a?(String) && CHECKSUM.match?(checksum)
    end
    duplicates(paths).each { |path| error(:duplicate_manifest_path, "manifest.yml.files", "Manifest path #{path} is duplicated") }
    validate_extra_payload(paths)
  end

  def verify_file(relative, checksum, location)
    path = @root.join(relative)
    unless contained_file?(path)
      error(:snapshot_file_missing_or_unsafe, "#{location}.path", "Manifest file is missing or unsafe: #{relative}")
      return
    end
    actual = Digest::SHA256.file(path).hexdigest
    error(:snapshot_checksum_mismatch, "#{location}.sha256", "Checksum mismatch for #{relative}") unless actual == checksum
  end

  def validate_extra_payload(manifest_paths)
    expected = (manifest_paths + CONTROL_FILES).to_set
    actual = @root.glob("**/*", File::FNM_DOTMATCH).select(&:file?).map do |path|
      path.relative_path_from(@root).each_filename.to_a.join("/")
    end
    (actual.to_set - expected).to_a.sort.each do |path|
      error(:unmanifested_snapshot_file, path, "Snapshot contains an unmanifested file")
    end
  end

  def validate_season_summary(manifest, catalog)
    summaries = manifest["seasons"]
    unless summaries.is_a?(Array)
      error(:invalid_manifest_seasons, "manifest.yml.seasons", "Manifest seasons must be a list")
      return
    end
    expected = catalog.seasons.map do |entry|
      {
        "code" => entry[:code],
        "order" => entry[:order],
        "metadata_checksum" => checksum_for(entry),
        "published_episode_count" => entry[:metadata].public_chapters.length
      }
    end
    error(:snapshot_season_summary_mismatch, "manifest.yml.seasons", "Manifest season summary does not match validated metadata") unless summaries == expected
  end

  def warn_nonpublic_published(catalog)
    catalog.seasons.each do |entry|
      next if %i[publishing completed].include?(entry[:metadata].season[:status])
      next if entry[:metadata].public_chapters.empty?

      warning(:published_in_nonpublic_season, "#{entry[:code]}.season.status", "Published episodes are hidden by the season status")
    end
  end

  def checksum_for(entry)
    Digest::SHA256.file(@root.join(entry[:path], "content_meta.yml")).hexdigest
  rescue Errno::ENOENT
    nil
  end

  def append_catalog_diagnostics(catalog)
    catalog.diagnostics.each do |diagnostic|
      @diagnostics << diagnostic
    end
  end

  def safe_relative_file?(value)
    return false unless value.is_a?(String) && value.present? && !value.include?("\\")

    path = Pathname.new(value)
    !path.absolute? && path.each_filename.none? { |part| %w[. ..].include?(part) } && path.to_s == value
  end

  def contained_file?(path)
    root = @root.realpath
    candidate = path.realpath
    path.file? && candidate.to_s.start_with?("#{root}#{File::SEPARATOR}")
  rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP
    false
  end

  def duplicates(values)
    values.tally.select { |_value, count| count > 1 }.keys.sort
  end

  def failure(code, location, message)
    error(code, location, message)
    ProductContent::RuntimeSnapshot.new(root: @root, manifest: nil, build_metadata: nil, catalog: nil, diagnostics: @diagnostics)
  end

  def error(code, location, message)
    diagnostic(:error, code, location, message)
  end

  def warning(code, location, message)
    diagnostic(:warning, code, location, message)
  end

  def diagnostic(severity, code, location, message)
    @diagnostics << ProductContent::SeasonMetadata::Diagnostic.new(severity:, code:, location:, message:)
  end
end
