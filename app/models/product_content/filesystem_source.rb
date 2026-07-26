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
    Dir.glob(path.join("[0-9][0-9]_*.md")).sort.filter_map do |file_path|
      next if meta.non_chapter_files.include?(File.basename(file_path))

      id = File.basename(file_path, ".md").split("_", 2).first
      kind = chapter_kind(id.to_i)
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
    normalized_id = id.to_s.rjust(2, "0")
    chapters.find { |chapter| chapter[:id] == normalized_id }
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
    meta.trial_chapter_limit
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

  private

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

      return line.sub(/^#+\s*/, "").strip
    end

    File.basename(file_path, ".md").tr("_", " ")
  end
end
