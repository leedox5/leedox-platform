require "digest"
require "fileutils"

module ContentSnapshot
  class Builder
    CORE_MANIFEST = "manifest.yml"
    BUILD_METADATA = "build.yml"

    def initialize(source_root:, source_commit:, target:, product_code: "chatdox", generated_at: Time.current)
      @source_root = Pathname.new(source_root).expand_path
      @source_commit = source_commit.to_s
      @target = Pathname.new(target).expand_path
      @product_code = product_code
      @generated_at = generated_at
    end

    def build!
      validate_commit!
      catalog = ProductContent::CatalogMetadataLoader.load(root: @source_root, expected_product_code: @product_code)
      raise Error.new(:catalog_invalid, diagnostic_summary(catalog)) unless catalog.valid?

      @target.dirname.mkpath
      directory = Dir.mktmpdir(".#{@target.basename}.tmp-", @target.dirname.to_s)
      begin
        staging = Pathname.new(directory)
        manifest = populate(staging, catalog)
        write_manifests(staging, manifest)
        atomic_publish!(staging)
      ensure
        FileUtils.rm_rf(directory) if File.exist?(directory)
      end
      @target
    end

    private

    def validate_commit!
      return if @source_commit.match?(/\A[0-9a-f]{40}\z/)

      raise Error.new(:invalid_source_commit, "Snapshot source commit must be a full 40-character Git SHA")
    end

    def populate(staging, catalog)
      file_entries = []
      copy_file(@source_root.join("catalog.yml"), staging.join("catalog.yml"), "catalog.yml", file_entries)

      season_entries = catalog.seasons.map do |entry|
        season_root = @source_root.join(entry[:path])
        target_root = staging.join(entry[:path])
        metadata_path = season_root.join("content_meta.yml")
        copy_file(metadata_path, target_root.join("content_meta.yml"), "#{entry[:path]}/content_meta.yml", file_entries)

        published = entry[:metadata].public_chapters
        published.each do |chapter|
          relative = "#{entry[:path]}/#{chapter[:slug]}.md"
          body_path = season_root.join("#{chapter[:slug]}.md")
          copy_file(body_path, staging.join(relative), relative, file_entries)
          copy_referenced_images(body_path, season_root, target_root, entry, file_entries)
        end

        {
          "code" => entry[:code],
          "order" => entry[:order],
          "metadata_checksum" => sha256(metadata_path),
          "published_episode_count" => published.length
        }
      end

      {
        "schema_version" => 1,
        "product_code" => @product_code,
        "source_commit" => @source_commit,
        "seasons" => season_entries,
        "files" => file_entries.uniq { |entry| entry["path"] }.sort_by { |entry| entry["path"] }
      }
    end

    def copy_referenced_images(body_path, season_root, target_root, entry, file_entries)
      images_dir = entry[:metadata].season[:images_dir]
      references = ImageReferences.extract(body_path.read, season_code: entry[:code], images_dir:)
      references.each do |relative_image|
        source = season_root.join(images_dir, relative_image)
        ensure_contained_file!(source, season_root.join(images_dir), :image_missing_or_unsafe)
        relative = "#{entry[:path]}/#{images_dir}/#{relative_image}"
        copy_file(source, target_root.join(images_dir, relative_image), relative, file_entries)
      end
    end

    def copy_file(source, destination, relative, file_entries)
      ensure_contained_file!(source, @source_root, :snapshot_file_missing_or_unsafe)
      destination.dirname.mkpath
      FileUtils.copy_file(source, destination)
      file_entries << { "path" => relative.tr("\\", "/"), "sha256" => sha256(destination) }
    end

    def ensure_contained_file!(path, root, code)
      root_realpath = root.realpath
      path_realpath = path.realpath
      contained = path_realpath.to_s.start_with?("#{root_realpath}#{File::SEPARATOR}")
      return if path.file? && contained

      raise Error.new(code, "Snapshot file is missing or resolves outside its allowed root: #{path.basename}")
    rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP
      raise Error.new(code, "Snapshot file is missing or inaccessible: #{path.basename}")
    end

    def write_manifests(staging, manifest)
      staging.join(CORE_MANIFEST).write(YAML.dump(manifest))
      build = {
        "schema_version" => 1,
        "source_commit" => @source_commit,
        "generated_at" => @generated_at.iso8601
      }
      staging.join(BUILD_METADATA).write(YAML.dump(build))
    end

    def atomic_publish!(staging)
      backup = @target.dirname.join(".#{@target.basename}.backup-#{SecureRandom.hex(6)}")
      had_target = @target.exist?
      File.rename(@target, backup) if had_target
      File.rename(staging, @target)
      FileUtils.rm_rf(backup) if had_target
    rescue StandardError
      File.rename(backup, @target) if had_target && backup.exist? && !@target.exist?
      raise
    end

    def diagnostic_summary(catalog)
      codes = catalog.diagnostics.map(&:code).uniq.join(", ")
      "Catalog validation failed: #{codes}"
    end

    def sha256(path)
      Digest::SHA256.file(path).hexdigest
    end
  end
end
