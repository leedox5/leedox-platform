class ClaudoxController < ApplicationController
  include ChapterImages

  CLAUDOX_PATH = Claudox::CLAUDOX_PATH

  def index
    @chapters = available_chapters
    @phase_chapters = chapters_by_phase(@chapters)
    @appendix_chapters = appendix_chapters(@chapters)
  end

  def image
    serve_chapter_image(CLAUDOX_PATH.join("images"), params[:filename])
  end

  def show
    @chapters = available_chapters
    @phase_chapters = chapters_by_phase(@chapters)
    @appendix_chapters = appendix_chapters(@chapters)
    @current_id = params[:id].to_s.rjust(2, "0")
    @current_chapter = @chapters.find { |chapter| chapter[:id] == @current_id }

    unless @current_chapter&.dig(:available)
      render plain: "아직 공개되지 않은 챕터입니다.", status: :not_found
      return
    end

    authorize @current_chapter, :view?, policy_class: DocPolicy

    file_path = CLAUDOX_PATH.join("#{@current_chapter[:slug]}.md")
    @last_updated_at = Claudox.last_updated_at(@current_chapter[:slug])
    raw_markdown = File.read(file_path)

    @content_html = render_markdown(strip_leading_heading(raw_markdown))
    @chapter_progress = if user_signed_in?
      current_user.chapter_progresses.find_by(chapter_id: @current_id, product_code: "claudox")
    end
  end

  private

  def available_chapters
    Claudox.all.map { |chapter| chapter.merge(accessible: DocPolicy.new(current_user, chapter).view?) }
  end

  def chapters_by_phase(chapters)
    Claudox.phases.map do |phase|
      phase_chapters = chapters.select { |chapter| phase[:range].cover?(chapter[:id].to_i) }
      available_count = phase_chapters.count { |chapter| chapter[:available] }

      phase.merge(
        chapters: phase_chapters,
        available_count: available_count,
        total_count: phase_chapters.size
      )
    end
  end

  # Appendices (90..99) sit outside the Part 1/2/3 story flow, so they don't
  # belong in chapters_by_phase's ranges -- they get their own flat list.
  def appendix_chapters(chapters)
    chapters.select { |chapter| chapter[:kind] == :appendix }
  end

  def strip_leading_heading(raw_markdown)
    raw_markdown.sub(/\A\s*#[^\n]*\n?/, "")
  end

  def render_markdown(raw_markdown)
    renderer = Redcarpet::Render::HTML.new(
      hard_wrap: true,
      link_attributes: { target: "_blank", rel: "noopener noreferrer" }
    )
    markdown = Redcarpet::Markdown.new(
      renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      superscript: true
    )

    markdown.render(raw_markdown).html_safe
  end
end
