class Claudox
  CLAUDOX_PATH = Rails.root.join("hq/claudox")

  # Regular 20-chapter story flow vs. out-of-flow "appendix" specials
  # (90..99 -- follows the existing 1~20-outside convention used by
  # 88_progress.md/97_commands.md, but unlike those trackers, appendices are
  # narrative chapters meant to be read).
  CHAPTER_RANGE = 1..20
  APPENDIX_RANGE = 90..99

  # 97_commands.md predates the appendix feature and happens to fall inside
  # 90..99 -- it's a command-shorthand reference for the HQ/DEV workflow, not
  # reader-facing content, so it must not surface as a browsable/licensed
  # "appendix chapter" just because its filename matches the number range.
  NON_CHAPTER_FILES = %w[97_commands.md].freeze

  PHASES = [
    {
      key: "part_1",
      label: "Part 1",
      title: "입문",
      description: "관계 맺기와 기본 협업 규칙 — Claudox와 처음 만나 이름을 정하고, 작업 규칙과 기억 체계를 세우는 단계.",
      range: 1..8
    },
    {
      key: "part_2",
      label: "Part 2",
      title: "중급",
      description: "실제 개발 워크플로우 — 폴더 구조부터 코드 리뷰, 테스트, Git/PR까지 엔지니어링 작업을 함께 처리하는 단계.",
      range: 9..15
    },
    {
      key: "part_3",
      label: "Part 3",
      title: "고급",
      description: "규모 확장과 메타적 자동화 — 서브에이전트와 워크플로우로 범위를 넓히고, 보안까지 챙기는 단계.",
      range: 16..20
    }
  ].freeze

  def self.phases
    PHASES
  end

  # Unlike Curriculum::CHAPTERS, Claudox has no hand-written chapter list --
  # its content lives as loose markdown files, so the chapter list is derived
  # by scanning the directory. Shared by ClaudoxController (chapter list/read
  # page) and ChapterProgressesController/DashboardController (chapter
  # progress + titles), so this scan only happens in one place.
  def self.all
    Dir.glob(CLAUDOX_PATH.join("[0-9][0-9]_*.md")).sort.filter_map do |file_path|
      next if NON_CHAPTER_FILES.include?(File.basename(file_path))

      id = File.basename(file_path, ".md").split("_", 2).first
      kind = chapter_kind(id.to_i)
      next unless kind

      {
        id: id,
        slug: File.basename(file_path, ".md"),
        title: extract_title(file_path),
        product_code: "claudox",
        available: true,
        kind: kind
      }
    end
  end

  def self.find(id)
    normalized_id = id.to_s.rjust(2, "0")
    all.find { |chapter| chapter[:id] == normalized_id }
  end

  def self.extract_title(file_path)
    File.foreach(file_path) do |line|
      next unless line.start_with?("#")

      return line.sub(/^#+\s*/, "").strip
    end

    File.basename(file_path, ".md").tr("_", " ")
  end
  private_class_method :extract_title

  def self.chapter_kind(chapter_number)
    return :chapter if CHAPTER_RANGE.cover?(chapter_number)
    return :appendix if APPENDIX_RANGE.cover?(chapter_number)

    nil
  end
  private_class_method :chapter_kind
end
