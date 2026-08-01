class ProductContent::ChatdoxSeasonedCompatibilityAdapter
  attr_reader :source, :product_code

  def initialize(product_code = "chatdox", snapshot_path: ProductContent.chatdox_snapshot_path)
    @product_code = product_code
    @source = ProductContent::ChatdoxSeasonedSource.new(product_code, snapshot_path:)
  end

  delegate :usable?, :diagnostics, :source_commit, to: :source

  def chapters
    source.public_chapters.select { |chapter| chapter[:season_code] == "s01" }.map do |chapter|
      chapter.merge(id: chapter[:display_number], canonical_id: chapter[:id]).freeze
    end
  end

  def public_chapters
    source.public_chapters
  end

  def find(id)
    chapters.find { |chapter| chapter[:id] == id.to_s.rjust(2, "0") }
  end

  def phases
    return [] unless usable?

    metadata = s01_entry&.dig(:metadata)
    return [] unless metadata

    metadata.phases.map do |phase|
      numbers = phase[:episode_ids].map { |id| id.delete_prefix("S01E").to_i }
      {
        key: phase[:key],
        label: phase[:title],
        title: phase[:title],
        description: nil,
        range: numbers.min..numbers.max
      }
    end
  end

  def guest_chapter_limit
    s01_entry&.fetch(:metadata)&.season&.fetch(:guest_episode_limit, 0) || 0
  end

  def trial_chapter_limit
    s01_entry&.fetch(:metadata)&.season&.fetch(:trial_episode_limit, 0) || 0
  end

  def licensed_chapter_ranges
    usable? ? [ 1..20 ] : []
  end

  def path
    source.snapshot.root.join("s01")
  end

  def images_path
    path.join("images")
  end

  def missing_chapter_message
    usable? ? "챕터를 찾을 수 없습니다." : "콘텐츠 snapshot을 사용할 수 없습니다."
  end

  def editorial_status(id)
    find(id) ? :written : :missing
  end

  def last_updated_at(_slug)
    Time.zone.parse(source.snapshot.build_metadata.fetch("generated_at"))
  rescue ArgumentError, KeyError
    nil
  end

  def theme
    { accent: "blue", label: "CHATDOX", back_link_label: "문서 목록", index_heading: "완전한 커리큘럼" }
  end

  private

  def s01_entry
    source.snapshot.catalog&.seasons&.find { |entry| entry[:code] == "s01" }
  end
end
