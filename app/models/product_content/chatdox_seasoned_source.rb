class ProductContent::ChatdoxSeasonedSource
  PUBLIC_SEASON_STATUSES = %i[publishing completed].freeze
  CANONICAL_ID = /\AS(\d{2})E(\d{2})\z/

  attr_reader :product_code, :snapshot

  def initialize(
    product_code = "chatdox",
    snapshot_path: ProductContent.chatdox_snapshot_path,
    expected_source_commit: ProductContent.chatdox_expected_source_commit
  )
    @product_code = product_code
    @snapshot = ProductContent::RuntimeSnapshotVerifier.verify(root: snapshot_path, expected_source_commit:)
  end

  def usable?
    snapshot.usable?
  end

  def diagnostics
    snapshot.diagnostics
  end

  def source_commit
    snapshot.source_commit
  end

  def seasons
    return [] unless usable?

    snapshot.catalog.seasons.map do |entry|
      metadata = entry[:metadata]
      {
        code: entry[:code],
        order: entry[:order],
        title: metadata.season[:title],
        status: metadata.season[:status],
        published_episode_count: metadata.public_chapters.length,
        public_episode_count: public_for_season?(metadata) ? metadata.public_chapters.length : 0
      }.freeze
    end.freeze
  end

  def chapters
    public_chapters
  end

  def public_chapters
    return [] unless usable?

    season_entries.filter_map do |entry|
      next unless public_for_season?(entry[:metadata])

      entry[:metadata].public_chapters.map { |chapter| decorate(chapter, entry) }
    end.flatten.freeze
  end

  def admin_chapters
    return [] unless usable?

    season_entries.flat_map do |entry|
      entry[:metadata].chapters.map do |chapter|
        decorate(chapter, entry, protected: chapter[:status] == :archived, admin: true)
      end
    end.freeze
  end

  def phases
    return [] unless usable?

    season_entries.filter_map do |entry|
      next unless public_for_season?(entry[:metadata])

      entry[:metadata].phases.map do |phase|
        phase.merge(season_code: entry[:code], season_order: entry[:order]).freeze
      end
    end.flatten.freeze
  end

  def find(id)
    canonical = canonical_id(id)
    return unless canonical

    public_chapters.find { |chapter| chapter[:id] == canonical }
  end

  def find_direct(id)
    canonical = canonical_id(id)
    return unless canonical && usable?

    chapter, entry = raw_chapter(canonical)
    return unless chapter
    if chapter[:status] == :published && public_for_season?(entry[:metadata])
      decorate(chapter, entry)
    elsif chapter[:status] == :archived && protected_body_path(chapter).file?
      decorate(chapter, entry, protected: true)
    end
  end

  def find_for_admin(id)
    canonical = canonical_id(id)
    return unless canonical && usable?

    chapter, entry = raw_chapter(canonical)
    decorate(chapter, entry, protected: chapter[:status] == :archived, admin: true) if chapter
  end

  def find_by(season_code:, episode_number:, context: :public)
    code = season_code.to_s.downcase
    return unless code.match?(/\As\d{2}\z/) && episode_number.to_s.match?(/\A\d{1,2}\z/)

    id = format("%sE%02d", code.upcase, episode_number.to_i)
    { public: method(:find), direct: method(:find_direct), admin: method(:find_for_admin) }.fetch(context).call(id)
  rescue KeyError
    nil
  end

  def legacy_s01_lookup(id)
    return unless id.to_s.match?(/\A\d{1,2}\z/)

    find(format("S01E%02d", id.to_i))
  end

  def body_path(chapter, context: :public)
    return unless usable? && chapter.is_a?(Hash)

    if context == :direct && chapter[:status] == :archived
      path = protected_body_path(chapter)
    elsif context == :admin && chapter[:status] == :archived
      path = protected_body_path(chapter)
    else
      return unless chapter[:status] == :published && PUBLIC_SEASON_STATUSES.include?(chapter[:season_status])
      path = snapshot.root.join(chapter[:season_code], "#{chapter[:slug]}.md")
    end
    contained_file(path) ? path : nil
  end

  def image_path(season_code:, relative_path:, context: :public)
    season = season_code.to_s.downcase
    return unless relative_path.to_s.present? && !relative_path.to_s.include?("\\")

    relative = Pathname.new(relative_path.to_s)
    return if relative.absolute? || relative.each_filename.any? { |part| %w[. ..].include?(part) }

    prefix = context == :direct ? snapshot.root.join("protected/archived") : snapshot.root
    path = prefix.join(season, "images", relative)
    contained_file(path) ? path : nil
  end

  private

  def season_entries
    snapshot.catalog.seasons
  end

  def public_for_season?(metadata)
    PUBLIC_SEASON_STATUSES.include?(metadata.season[:status])
  end

  def canonical_id(value)
    string = value.to_s.upcase
    CANONICAL_ID.match?(string) ? string : nil
  end

  def raw_chapter(id)
    season_code = "s#{id[1, 2]}"
    entry = season_entries.find { |candidate| candidate[:code] == season_code }
    return unless entry

    chapter = entry[:metadata].chapters.find { |candidate| candidate[:id] == id }
    [ chapter, entry ]
  end

  def decorate(chapter, entry, protected: false, admin: false)
    body = if protected
      protected_body_path(chapter)
    else
      snapshot.root.join(entry[:path], "#{chapter[:slug]}.md")
    end
    chapter.merge(
      season_status: entry[:metadata].season[:status],
      file_present: contained_file(body),
      available: chapter[:status] == :published && public_for_season?(entry[:metadata]) && contained_file(body),
      protected: protected,
      admin_preview: admin
    ).freeze
  end

  def protected_body_path(chapter)
    snapshot.root.join("protected/archived", chapter[:season_code], "#{chapter[:slug]}.md")
  end

  def contained_file(path)
    root = snapshot.root.realpath
    candidate = path.realpath
    path.file? && candidate.to_s.start_with?("#{root}#{File::SEPARATOR}")
  rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP
    false
  end
end
