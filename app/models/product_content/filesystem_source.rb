# Default content source for any product not explicitly registered in
# ProductContent.registry -- scans hq/<product_code>/*.md by convention
# (this is Claudox's original approach, generalized to take the product code
# as a parameter instead of being hardcoded to "claudox").
class ProductContent::FilesystemSource
  UNWRITTEN_PLACEHOLDER = "*(아직 작성되지 않음)*"

  attr_reader :product_code

  def initialize(product_code)
    @product_code = product_code
  end

  def path
    Rails.root.join("hq/#{product_code}")
  end

  def images_path
    path.join("images")
  end

  def chapters
    chapter_files = Dir.glob(path.join("[0-9][0-9]_*.md")) + Dir.glob(path.join("S[0-9][0-9]*_*.md"))
    chapter_files.sort.filter_map do |file_path|
      next if meta.non_chapter_files.include?(File.basename(file_path))

      id = File.basename(file_path, ".md").split("_", 2).first
      number = extract_chapter_number(id)
      kind = chapter_kind(number)
      next unless kind

      {
        id: id,
        slug: File.basename(file_path, ".md"),
        title: extract_title(file_path),
        product_code: product_code,
        available: true,
        kind: kind
      }
    end
  end

  def find(id)
    id_str = id.to_s
    chapters.find { |chapter| chapter[:id] == id_str || chapter[:id] == id_str.rjust(2, "0") }
  end

  def phases
    meta.phases
  end

  def licensed_chapter_ranges
    meta.licensed_chapter_ranges
  end

  def guest_chapter_limit
    meta.guest_chapter_limit
  end

  def trial_chapter_limit
    db_limit = Product.find_by(code: product_code)&.trial_chapter_limit
    db_limit.presence || meta.trial_chapter_limit
  end

  def missing_chapter_message
    "아직 공개되지 않은 챕터입니다."
  end

  def editorial_status(id)
    chapter = find(id)
    return :missing unless chapter

    file_path = path.join("#{chapter[:slug]}.md")
    File.read(file_path).include?(UNWRITTEN_PLACEHOLDER) ? :draft : :written
  end

  def last_updated_at(slug)
    ContentManifest.last_updated_at(path, slug)
  end

  def theme
    meta.theme
  end

  private

  def extract_chapter_number(id)
    if match = id.to_s.match(/\A[A-Z0-9]+E(\d+)\z/i)
      match[1].to_i
    else
      id.to_i
    end
  end

  def meta
    @meta ||= ProductContent::ContentMeta.load(path)
  end

  def chapter_kind(chapter_number)
    return :chapter if meta.chapter_range.cover?(chapter_number)
    return :appendix if meta.appendix_range&.cover?(chapter_number)

    nil
  end

  def extract_title(file_path)
    File.foreach(file_path) do |line|
      next unless line.start_with?("#")

      # HQ's markdown headings carry their own "N. " chapter-number prefix
      # (e.g. "# 1. 오늘, AI와 첫 만남") -- the screen already shows the
      # chapter number as its own UI element, so keeping the prefix here
      # would duplicate it ("01. 1. 오늘..."). Strip it at parse time only;
      # the source markdown files are untouched.
      heading = line.sub(/^#+\s*/, "").strip
      return heading.sub(/\A\d+\.\s*/, "")
    end

    File.basename(file_path, ".md").tr("_", " ")
  end
end
