module ChatdoxRelease
  class Readiness
    Result = Data.define(
      :state, :reason, :source_mode, :expected_commit, :installed_commit,
      :schema_version, :generated_at, :seasons, :diagnostics, :canonical_routes,
      :legacy_rollback, :progress_inventory
    )

    REASONS = {
      snapshot_unreadable: :snapshot_missing,
      snapshot_control_file_missing: :manifest_missing,
      invalid_snapshot_document: :manifest_invalid,
      snapshot_yaml_error: :manifest_invalid,
      invalid_manifest_schema: :manifest_invalid,
      invalid_build_schema: :manifest_invalid,
      invalid_manifest_source_commit: :manifest_invalid,
      snapshot_commit_mismatch: :manifest_invalid,
      unexpected_snapshot_source_commit: :source_commit_mismatch,
      catalog_invalid: :catalog_invalid,
      snapshot_checksum_mismatch: :checksum_mismatch,
      snapshot_file_missing_or_unsafe: :published_body_missing,
      image_missing_or_unsafe: :published_image_missing,
      unsafe_manifest_path: :unsafe_path,
      unmanifested_snapshot_file: :unsafe_path
    }.freeze

    def self.call = new.call

    def call
      mode = ProductContent.chatdox_source_mode
      expected = ProductContent.chatdox_expected_source_commit
      return result(:not_configured, :source_not_configured, mode:, expected:) unless mode == "seasoned"
      return result(:blocked, :expected_commit_missing, mode:, expected:) unless expected&.match?(ProductContent::RuntimeSnapshotVerifier::SHA)

      source = ProductContent.seasoned_chatdox
      diagnostics = source.diagnostics
      reason = primary_reason(diagnostics)
      state = source.usable? ? (diagnostics.any? { |item| item.severity == :warning } ? :warning : :ready) : :blocked
      snapshot = source.snapshot

      Result.new(
        state:, reason: source.usable? ? :ready : reason, source_mode: mode,
        expected_commit: abbreviated(expected), installed_commit: abbreviated(snapshot.source_commit),
        schema_version: snapshot.manifest&.fetch("schema_version", nil),
        generated_at: safe_generated_at(snapshot), seasons: safe_seasons(source),
        diagnostics: summarize(diagnostics), canonical_routes: source.usable?, legacy_rollback: true,
        progress_inventory: :not_run
      )
    rescue StandardError => error
      Rails.logger.error("chatdox_readiness reason=manifest_invalid error=#{error.class.name}")
      result(:blocked, :manifest_invalid, mode: ProductContent.chatdox_source_mode, expected: nil)
    end

    private

    def result(state, reason, mode:, expected:)
      Result.new(
        state:, reason:, source_mode: mode, expected_commit: abbreviated(expected), installed_commit: nil,
        schema_version: nil, generated_at: nil, seasons: [], diagnostics: [], canonical_routes: false,
        legacy_rollback: true, progress_inventory: :not_run
      )
    end

    def primary_reason(diagnostics)
      code = diagnostics.find { |item| item.severity == :error }&.code
      REASONS.fetch(code, :manifest_invalid)
    end

    def summarize(diagnostics)
      diagnostics.group_by { |item| [ item.severity, REASONS.fetch(item.code, item.code) ] }
        .map { |(severity, code), items| { severity:, code:, count: items.length } }
        .sort_by { |item| [ item[:severity].to_s, item[:code].to_s ] }
    end

    def safe_seasons(source)
      source.seasons.map do |season|
        { code: season[:code], status: season[:status], public_episode_count: season[:public_episode_count] }
      end
    end

    def safe_generated_at(snapshot)
      value = snapshot.build_metadata&.fetch("generated_at", nil)
      Time.zone.parse(value).iso8601 if value
    rescue ArgumentError
      nil
    end

    def abbreviated(value)
      value&.first(12)
    end
  end
end
