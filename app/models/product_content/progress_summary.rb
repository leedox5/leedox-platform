class ProductContent::ProgressSummary
  Segment = Data.define(
    :completed_count, :available_count, :percentage, :next_chapter, :available, :status
  ) do
    def available? = available
    def complete? = available? && completed_count == available_count
  end

  Result = Data.define(:overall, :seasons, :status) do
    def season(code) = seasons[code.to_s.downcase]
    def available? = status == :available
  end

  def self.call(user:, source:)
    new(user:, source:).call
  end

  def initialize(user:, source:)
    @user = user
    @source = source
  end

  def call
    return unavailable_result unless source_usable?

    chapters = public_chapters
    completed_ids = completed_canonical_ids
    grouped = chapters.group_by { |chapter| season_code(chapter) }
    source_season_codes.each { |code| grouped[code] ||= [] }
    seasons = grouped.transform_values { |season_chapters| segment(season_chapters, completed_ids) }.freeze

    Result.new(overall: segment(chapters, completed_ids), seasons:, status: :available).freeze
  end

  private

  attr_reader :user, :source

  def source_usable?
    !source.respond_to?(:usable?) || source.usable?
  end

  def public_chapters
    chapters = source.respond_to?(:public_chapters) ? source.public_chapters : source.chapters
    chapters.select { |chapter| chapter[:available] && chapter[:kind] != :appendix }.freeze
  end

  def completed_canonical_ids
    return Set.new unless user

    ids = user.chapter_progresses.where(product_code: source.product_code).completed.pluck(:chapter_id)
    ids.filter_map do |id|
      ProductContent::ChapterIdentity.canonicalize(product_code: source.product_code, chapter_id: id, source:)
    end.to_set
  end

  def segment(chapters, completed_ids)
    canonical = chapters.map { |chapter| canonical_id(chapter) }
    completed_count = canonical.count { |id| completed_ids.include?(id) }
    available_count = chapters.length
    next_chapter = chapters.zip(canonical).find { |_chapter, id| completed_ids.exclude?(id) }&.first

    Segment.new(
      completed_count:,
      available_count:,
      percentage: available_count.zero? ? 0 : ((completed_count.to_f / available_count) * 100).round,
      next_chapter:,
      available: available_count.positive?,
      status: available_count.zero? ? :unavailable : (next_chapter ? :in_progress : :complete)
    ).freeze
  end

  def canonical_id(chapter)
    chapter[:canonical_id] || ProductContent::ChapterIdentity.canonicalize(
      product_code: source.product_code, chapter_id: chapter[:id], source:
    ) || chapter[:id]
  end

  def season_code(chapter)
    return chapter[:season_code].to_s.downcase if chapter[:season_code]

    canonical_id(chapter).to_s[/\AS(\d{2})E/, 1]&.then { |number| "s#{number}" } || "default"
  end

  def source_season_codes
    return [] unless source.respond_to?(:seasons)

    source.seasons.map { |season| season[:code].to_s.downcase }
  end

  def unavailable_result
    empty = Segment.new(
      completed_count: 0, available_count: 0, percentage: 0,
      next_chapter: nil, available: false, status: :unavailable
    ).freeze
    Result.new(overall: empty, seasons: {}.freeze, status: :unavailable).freeze
  end
end
