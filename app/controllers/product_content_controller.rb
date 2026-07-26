# Replaces DocsController + ClaudoxController. Both legacy URLs (/docs/*,
# /claudox/read/*) and the new generic /content/:product_code/* pattern route
# here, with product_code coming from route `defaults:` for the legacy paths
# (see config/routes.rb) -- see docs/internal/content_platform_design.md
# section B.
#
# Chatdox and Claudox keep their existing, visually distinct templates
# (app/views/docs/*, app/views/claudox/*) -- unifying the controller doesn't
# mean unifying the screens, and "동작 완전히 동일 유지" means the pixels
# shouldn't move either. A product with neither gets a plain generic
# template (app/views/product_content/*) as a working default.
class ProductContentController < ApplicationController
  include ChapterImages

  TEMPLATE_DIRS = {
    "chatdox" => "docs",
    "claudox" => "claudox"
  }.freeze

  def index
    load_common
    render template: "#{template_dir}/index"
  end

  def show
    @product_code = params[:product_code]
    # Only Chatdox's original controller forced this; preserved exactly
    # rather than applying it to both out of tidiness.
    request.format = :html if @product_code == "chatdox"

    load_common
    @current_id = params[:id].to_s.rjust(2, "0")
    @current_chapter = @source.find(@current_id)

    if @current_chapter.nil?
      render plain: @source.missing_chapter_message, status: :not_found
      return
    end

    unless @current_chapter[:available]
      render plain: "아직 공개되지 않은 챕터입니다.", status: :not_found
      return
    end

    authorize @current_chapter, :view?, policy_class: DocPolicy

    file_path = @source.path.join("#{@current_chapter[:slug]}.md")
    @last_updated_at = @source.last_updated_at(@current_chapter[:slug])
    raw_markdown = File.read(file_path)
    # Claudox's templates show the title as their own <h1> already, so the
    # markdown body's leading "# ..." heading line would otherwise repeat it.
    # Chatdox's body has always rendered its leading heading inline (its
    # <h1> title comes from the hand-written chapter list, not the file) --
    # keeping that exactly as before rather than "fixing" a visible change.
    raw_markdown = strip_leading_heading(raw_markdown) if @product_code == "claudox"
    @content_html = render_markdown(raw_markdown)

    @chapter_progress = if user_signed_in?
      current_user.chapter_progresses.find_by(chapter_id: @current_id, product_code: @product_code)
    end

    render template: "#{template_dir}/show", formats: :html
  end

  def image
    serve_chapter_image(ProductContent.for(params[:product_code]).images_path, params[:filename])
  end

  private

  def load_common
    @product_code ||= params[:product_code]
    @source = ProductContent.for(@product_code)
    @chapters = available_chapters
    @phase_chapters = chapters_by_phase(@chapters)
    @appendix_chapters = appendix_chapters(@chapters)
    # Chatdox/Claudox define phases covering every chapter 1..20, so this is
    # always empty for them (no visual change). A product with no
    # content_meta.yml at all has zero phases, so without this every chapter
    # would exist and be individually reachable but never listed anywhere.
    @ungrouped_chapters = ungrouped_chapters(@chapters)
  end

  def template_dir
    TEMPLATE_DIRS.fetch(@product_code, "product_content")
  end

  def available_chapters
    @source.chapters.map { |chapter| chapter.merge(accessible: DocPolicy.new(current_user, chapter).view?) }
  end

  def chapters_by_phase(chapters)
    @source.phases.map do |phase|
      phase_chapters = chapters.select { |chapter| phase[:range].cover?(chapter[:id].to_i) }
      available_count = phase_chapters.count { |chapter| chapter[:available] }

      phase.merge(
        chapters: phase_chapters,
        available_count: available_count,
        total_count: phase_chapters.size
      )
    end
  end

  # Appendices (when a product has any) sit outside the phase/part groupings.
  def appendix_chapters(chapters)
    chapters.select { |chapter| chapter[:kind] == :appendix }
  end

  def ungrouped_chapters(chapters)
    grouped_ids = @phase_chapters.flat_map { |phase| phase[:chapters] }.map { |chapter| chapter[:id] }
    chapters.reject { |chapter| chapter[:kind] == :appendix || grouped_ids.include?(chapter[:id]) }
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
