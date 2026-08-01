class ProductContent::SeasonMetadataValidator
  SCHEMA_VERSION = 1
  SEASON_CODE = /\As\d{2}\z/
  EPISODE_ID = /\AS(\d{2})E(\d{2})\z/
  SAFE_KEY = /\A[a-z][a-z0-9_]*\z/
  SAFE_BASENAME = /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/
  SEASON_STATUSES = %w[draft upcoming publishing completed archived].freeze
  EPISODE_STATUSES = %w[draft review published archived].freeze
  GLOBAL_CODES = %i[
    invalid_document missing_schema_version unsupported_schema_version invalid_season
    season_directory_mismatch invalid_season_order missing_season_title unknown_season_status
    invalid_guest_limit invalid_trial_limit guest_limit_exceeds_trial_limit unsafe_images_dir
    duplicate_episode_id duplicate_episode_number duplicate_episode_order duplicate_episode_slug
    invalid_episode_collection invalid_phase_collection invalid_phase invalid_phase_key
    invalid_phase_order missing_phase_title invalid_phase_episode_ids duplicate_phase_membership
    duplicate_phase_key duplicate_phase_order unknown_phase_episode
  ].freeze

  def initialize(root:, product_code:, raw:)
    @root = Pathname.new(root).expand_path
    @product_code = product_code
    @raw = raw
    @diagnostics = []
    @invalid_episode_indexes = Set.new
  end

  def call
    unless @raw.is_a?(Hash)
      error(:invalid_document, "root", "Metadata root must be a mapping")
      return result
    end

    validate_schema
    season = validate_season
    phases = validate_phases
    episodes = validate_episodes(season, phases)
    validate_phase_membership(phases, episodes)

    if global_error?
      result(season:, phases: [], chapters: [])
    else
      chapters = compile_chapters(season, episodes)
      result(season:, phases: normalize_phases(phases), chapters:)
    end
  end

  private

  def validate_schema
    version = @raw["schema_version"]
    if version.nil?
      error(:missing_schema_version, "schema_version", "Schema version is required; supported version is 1")
    elsif version != SCHEMA_VERSION
      error(:unsupported_schema_version, "schema_version", "Unsupported schema version #{version.inspect}; supported version is 1")
    end
  end

  def validate_season
    value = hash_at("season")
    code = value["code"]
    order = value["order"]
    title = value["title"]
    status = value["status"]
    guest_limit = value["guest_episode_limit"]
    trial_limit = value["trial_episode_limit"]
    images_dir = value["images_dir"]

    error(:invalid_season, "season.code", "Season code must match sNN") unless code.is_a?(String) && SEASON_CODE.match?(code)
    if code.is_a?(String) && @root.basename.to_s != code
      error(:season_directory_mismatch, "season.code", "Season code #{code} does not match directory #{@root.basename}")
    end
    error(:invalid_season_order, "season.order", "Season order must be a positive integer") unless positive_integer?(order)
    error(:missing_season_title, "season.title", "Season title is required") unless present_string?(title)
    error(:unknown_season_status, "season.status", "Unknown season status #{status.inspect}") unless SEASON_STATUSES.include?(status)
    error(:invalid_guest_limit, "season.guest_episode_limit", "Guest episode limit must be a non-negative integer") unless non_negative_integer?(guest_limit)
    error(:invalid_trial_limit, "season.trial_episode_limit", "Trial episode limit must be a non-negative integer") unless non_negative_integer?(trial_limit)
    if non_negative_integer?(guest_limit) && non_negative_integer?(trial_limit) && guest_limit > trial_limit
      error(:guest_limit_exceeds_trial_limit, "season.guest_episode_limit", "Guest limit cannot exceed trial limit")
    end

    image_path = safe_relative_path(images_dir, "season.images_dir", :unsafe_images_dir)
    {
      code:, order:, title:, status: status&.to_sym,
      guest_episode_limit: guest_limit,
      trial_episode_limit: trial_limit,
      images_dir:,
      images_path: image_path
    }
  end

  def validate_phases
    values = @raw["phases"]
    unless values.is_a?(Array)
      error(:invalid_phase_collection, "phases", "Phases must be a list")
      return []
    end

    phases = values.each_with_index.map do |value, index|
      location = "phases[#{index}]"
      unless value.is_a?(Hash)
        error(:invalid_phase, location, "Phase must be a mapping")
        next { index:, episode_ids: [] }
      end

      key = value["key"]
      order = value["order"]
      title = value["title"]
      episode_ids = value["episode_ids"]
      error(:invalid_phase_key, "#{location}.key", "Phase key must use lowercase letters, numbers, and underscores") unless key.is_a?(String) && SAFE_KEY.match?(key)
      error(:invalid_phase_order, "#{location}.order", "Phase order must be a positive integer") unless positive_integer?(order)
      error(:missing_phase_title, "#{location}.title", "Phase title is required") unless present_string?(title)
      unless episode_ids.is_a?(Array) && episode_ids.all? { |id| id.is_a?(String) }
        error(:invalid_phase_episode_ids, "#{location}.episode_ids", "Phase episode IDs must be a list of strings")
        episode_ids = []
      end
      duplicates(episode_ids).each do |id|
        error(:duplicate_phase_membership, "#{location}.episode_ids", "Episode ID #{id} is repeated in this phase")
      end
      { index:, key:, order:, title:, episode_ids: }
    end

    duplicate_field_errors(phases, :key, :duplicate_phase_key, "phases", "Phase key")
    duplicate_field_errors(phases, :order, :duplicate_phase_order, "phases", "Phase order")
    phases
  end

  def validate_episodes(season, phases)
    values = @raw["episodes"]
    unless values.is_a?(Array)
      error(:invalid_episode_collection, "episodes", "Episodes must be a list")
      return []
    end

    phase_keys = phases.filter_map { |phase| phase[:key] }.to_set
    episodes = values.each_with_index.map do |value, index|
      location = "episodes[#{index}]"
      unless value.is_a?(Hash)
        episode_error(index, :invalid_episode, location, "Episode must be a mapping")
        next { index: }
      end

      episode = {
        index:,
        id: value["id"],
        number: value["number"],
        order: value["order"],
        slug: value["slug"],
        title: value["title"],
        status: value["status"],
        phase: value["phase"],
        published_at: value["published_at"]
      }
      validate_episode_fields(episode, season, phase_keys)
      episode
    end

    duplicate_episode_fields(episodes)
    episodes
  end

  def validate_episode_fields(episode, season, phase_keys)
    index = episode[:index]
    location = "episodes[#{index}]"
    id_match = episode[:id].is_a?(String) && EPISODE_ID.match(episode[:id])
    episode_error(index, :invalid_episode_id, "#{location}.id", "Episode ID must match SNNENN") unless id_match
    if id_match && season[:code].is_a?(String) && id_match[1] != season[:code].delete_prefix("s")
      episode_error(index, :episode_season_mismatch, "#{location}.id", "Episode ID season does not match metadata season")
    end
    unless positive_integer?(episode[:number])
      episode_error(index, :invalid_episode_number, "#{location}.number", "Episode number must be a positive integer")
    end
    if id_match && positive_integer?(episode[:number]) && id_match[2].to_i != episode[:number]
      episode_error(index, :episode_number_mismatch, "#{location}.number", "Episode number does not match its ID")
    end
    episode_error(index, :invalid_episode_order, "#{location}.order", "Episode order must be a positive integer") unless positive_integer?(episode[:order])
    unless episode[:slug].is_a?(String) && SAFE_BASENAME.match?(episode[:slug])
      episode_error(index, :unsafe_episode_slug, "#{location}.slug", "Episode slug must be a safe filename basename")
    end
    episode_error(index, :missing_episode_title, "#{location}.title", "Episode title is required") unless present_string?(episode[:title])
    unless EPISODE_STATUSES.include?(episode[:status])
      episode_error(index, :unknown_episode_status, "#{location}.status", "Unknown episode status #{episode[:status].inspect}")
    end
    unless episode[:phase].is_a?(String) && phase_keys.include?(episode[:phase])
      episode_error(index, :unknown_episode_phase, "#{location}.phase", "Episode must reference an existing phase")
    end

    episode[:published_at] = parse_published_at(episode[:published_at], index)
    validate_body(episode) if episode[:status] == "published"
  end

  def validate_body(episode)
    return unless episode[:slug].is_a?(String) && SAFE_BASENAME.match?(episode[:slug])

    path = @root.join("#{episode[:slug]}.md")
    unless path.file?
      episode_error(episode[:index], :published_body_missing, "episodes[#{episode[:index]}].slug", "Published episode body file is missing")
      return
    end
    return if contained_realpath?(path)

    episode_error(episode[:index], :body_path_escape, "episodes[#{episode[:index]}].slug", "Episode body resolves outside the season directory")
  end

  def validate_phase_membership(phases, episodes)
    episode_by_id = episodes.index_by { |episode| episode[:id] }
    memberships = Hash.new { |hash, key| hash[key] = [] }
    phases.each do |phase|
      phase[:episode_ids].each do |id|
        memberships[id] << phase[:key]
        error(:unknown_phase_episode, "phases[#{phase[:index]}].episode_ids", "Phase references unknown episode ID #{id}") unless episode_by_id.key?(id)
      end
    end

    memberships.each do |id, keys|
      next unless keys.uniq.length > 1

      episode = episode_by_id[id]
      if episode
        episode_error(episode[:index], :duplicate_episode_membership, "phases", "Episode ID #{id} belongs to multiple phases")
      else
        error(:duplicate_episode_membership, "phases", "Episode ID #{id} belongs to multiple phases")
      end
    end

    episodes.each do |episode|
      next unless episode[:id].is_a?(String)

      expected = episode[:phase]
      actual = memberships[episode[:id]]
      if actual.empty?
        episode_error(episode[:index], :orphan_episode, "episodes[#{episode[:index]}].phase", "Episode is not listed in its phase")
      elsif expected.is_a?(String) && actual.exclude?(expected)
        episode_error(episode[:index], :phase_membership_mismatch, "episodes[#{episode[:index]}].phase", "Episode phase and phase membership do not match")
      end
    end
  end

  def duplicate_episode_fields(episodes)
    {
      id: [ :duplicate_episode_id, "Episode ID" ],
      number: [ :duplicate_episode_number, "Episode number" ],
      order: [ :duplicate_episode_order, "Episode order" ],
      slug: [ :duplicate_episode_slug, "Episode slug" ]
    }.each do |field, (code, label)|
      values = episodes.filter_map { |episode| episode[field] }
      duplicates(values).each do |value|
        error(code, "episodes", "#{label} #{value} is duplicated")
      end
    end
  end

  def compile_chapters(season, episodes)
    published = episodes.select { |episode| episode[:status] == "published" }.sort_by { |episode| episode[:order] || Float::INFINITY }
    published_rank = published.each_with_index.to_h { |episode, index| [ episode[:index], index + 1 ] }

    episodes.reject { |episode| @invalid_episode_indexes.include?(episode[:index]) }
      .sort_by { |episode| episode[:order] }
      .map do |episode|
        status = episode[:status].to_sym
        rank = published_rank[episode[:index]]
        tier = access_tier(status, rank, season)
        {
          id: episode[:id],
          season_code: season[:code],
          season_order: season[:order],
          episode_number: episode[:number],
          episode_order: episode[:order],
          display_number: episode[:number].to_s.rjust(2, "0"),
          slug: episode[:slug],
          title: episode[:title],
          status:,
          access_tier: tier,
          kind: :chapter,
          product_code: @product_code,
          file_present: body_present?(episode),
          available: status == :published && body_present?(episode),
          manifest_key: "#{season[:code]}/#{episode[:slug]}.md",
          phase_key: episode[:phase],
          published_at: episode[:published_at]
        }
      end
  end

  def access_tier(status, rank, season)
    return :unpublished if %i[draft review].include?(status)
    return :archived if status == :archived
    return :guest if rank <= season[:guest_episode_limit]
    return :trial if rank <= season[:trial_episode_limit]

    :license
  end

  def normalize_phases(phases)
    phases.sort_by { |phase| phase[:order] }.map do |phase|
      { key: phase[:key], order: phase[:order], title: phase[:title], episode_ids: phase[:episode_ids].dup.freeze }
    end
  end

  def parse_published_at(value, index)
    return nil if value.nil?
    unless value.is_a?(String)
      episode_error(index, :invalid_published_at, "episodes[#{index}].published_at", "Published timestamp must be an ISO 8601 string")
      return nil
    end

    Time.iso8601(value).in_time_zone
  rescue ArgumentError
    episode_error(index, :invalid_published_at, "episodes[#{index}].published_at", "Published timestamp must be a valid ISO 8601 value")
    nil
  end

  def safe_relative_path(value, location, code)
    unless value.is_a?(String) && SAFE_BASENAME.match?(value)
      error(code, location, "Path must be a safe relative directory name")
      return
    end

    path = @root.join(value)
    if path.exist? && !contained_realpath?(path)
      error(code, location, "Path resolves outside the season directory")
      return
    end
    path
  end

  def contained_realpath?(path)
    root_realpath = @root.realpath
    candidate = path.realpath
    candidate == root_realpath || candidate.to_s.start_with?("#{root_realpath}#{File::SEPARATOR}")
  rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP
    false
  end

  def body_present?(episode)
    path = @root.join("#{episode[:slug]}.md")
    path.file? && contained_realpath?(path)
  end

  def hash_at(key)
    value = @raw[key]
    return value if value.is_a?(Hash)

    error(:invalid_season, key, "#{key.capitalize} must be a mapping")
    {}
  end

  def duplicate_field_errors(values, field, code, location, label)
    duplicates(values.filter_map { |value| value[field] }).each do |value|
      error(code, location, "#{label} #{value} is duplicated")
    end
  end

  def duplicates(values)
    values.tally.select { |_value, count| count > 1 }.keys.sort_by(&:to_s)
  end

  def episode_error(index, code, location, message)
    @invalid_episode_indexes << index
    error(code, location, message)
  end

  def error(code, location, message)
    @diagnostics << ProductContent::SeasonMetadata::Diagnostic.new(
      severity: :error,
      code:,
      location:,
      message:
    )
  end

  def global_error?
    @diagnostics.any? { |diagnostic| GLOBAL_CODES.include?(diagnostic.code) }
  end

  def result(season: nil, phases: [], chapters: [])
    ProductContent::SeasonMetadata.new(
      season: season && season.except(:images_path).freeze,
      phases:,
      chapters:,
      diagnostics: @diagnostics,
      images_path: season&.dig(:images_path)
    )
  end

  def positive_integer?(value)
    value.is_a?(Integer) && value.positive?
  end

  def non_negative_integer?(value)
    value.is_a?(Integer) && value >= 0
  end

  def present_string?(value)
    value.is_a?(String) && value.present?
  end
end
