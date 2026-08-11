# Replaces DocsController + ClaudoxController. Both legacy URLs (/docs/*,
# /claudox/read/*) and the new generic /content/:product_code/* pattern route
# here, with product_code coming from route `defaults:` for the legacy paths
# (see config/routes.rb) -- see docs/internal/content_platform_design.md
# section B.
#
# Every product renders through the same app/views/product_content/* templates
# now (see leedox_content_template_unification_r1) -- structure (layout,
# sidebar, number handling) is fully shared; only the theme data returned by
# each ProductContent source (accent color, sidebar label) still varies per
# product.
class ProductContentController < ApplicationController
  include ChapterImages

  helper_method :product_content_index_path_for, :product_chapter_path_for

  def index
    load_common
  end

  def show
    @product_code = params[:product_code]
    request.format = :html

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

    slug = @current_chapter[:slug].to_s
    unless slug.match?(/\A[\w-]+\z/)
      render plain: "챕터를 찾을 수 없습니다.", status: :not_found
      return
    end

    file_path = chapter_file_path(slug)
    unless file_path
      render plain: "챕터를 찾을 수 없습니다.", status: :not_found
      return
    end

    @last_updated_at = @source.last_updated_at(slug)
    # Every template now shows the chapter title as its own <h1>, so the
    # markdown body's leading "# ..." heading would otherwise repeat it --
    # applies to every product now, not just Claudox (see stage 3 -- Chatdox
    # was left out at the time because its old hand-written title didn't
    # always match the file's heading text; that's still true, but it no
    # longer matters here since this only strips whatever heading line is
    # actually in the file, independent of what title is displayed above it).
    raw_markdown = strip_leading_heading(File.read(file_path))
    @content_html = render_markdown(raw_markdown)

    @chapter_progress = if user_signed_in?
      current_user.chapter_progresses.find_by(chapter_id: @current_id, product_code: @product_code)
    end

    render formats: :html
  rescue Pundit::NotAuthorizedError
    # ApplicationController's rescue_from is shared by 13+ unrelated authorize
    # call sites app-wide (admin access, refunds, ...), so it stays generic on
    # purpose -- this local rescue gives locked *chapters* specifically a
    # context-aware landing spot instead (handoff 0045 R2-4). Guests are
    # deliberately left alone: re-raising lets them fall through to the
    # existing sign-in redirect, whose messaging is already contextual enough.
    raise unless user_signed_in?

    redirect_to locked_chapter_redirect_path, alert: "이 챕터는 라이선스가 필요합니다. 아래에서 이용 기간을 선택할 수 있습니다."
  end

  def image
    serve_chapter_image(ProductContent.for(params[:product_code]).images_path, params[:filename])
  end

  private

  def load_common
    @product_code ||= params[:product_code]
    @source = ProductContent.for(@product_code)
    @product = Product.find_by(code: @product_code)
    @display_name = @product&.name || @product_code.titleize
    @theme = @source.theme
    @chapters = available_chapters
    @phase_chapters = chapters_by_phase(@chapters)
    @appendix_chapters = appendix_chapters(@chapters)
    # Chatdox/Claudox define phases covering every chapter 1..20, so this is
    # always empty for them (no visual change). A product with no
    # content_meta.yml at all has zero phases, so without this every chapter
    # would exist and be individually reachable but never listed anywhere.
    @ungrouped_chapters = ungrouped_chapters(@chapters)
  end

  def available_chapters
    @source.chapters.map { |chapter| chapter.merge(accessible: DocPolicy.new(current_user, chapter).view?) }
  end

  def chapters_by_phase(chapters)
    @source.phases.map do |phase|
      phase_chapters = if phase[:range]
        chapters.select { |chapter| phase[:range].cover?(extract_chapter_number(chapter[:id])) }
      else
        []
      end
      available_count = phase_chapters.count { |chapter| chapter[:available] }

      phase.merge(
        chapters: phase_chapters,
        available_count: available_count,
        total_count: phase_chapters.size
      )
    end
  end

  private

  def extract_chapter_number(id)
    if match = id.to_s.match(/\A[A-Z0-9]+E(\d+)\z/i)
      match[1].to_i
    else
      id.to_i
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

  # Chatdox/Claudox chapter links (index list, sidebar, prev/next, back-link)
  # keep pointing at each product's own pre-existing legacy path here, rather
  # than switching to the generic /content/:product_code route the way
  # dashboard-generated links already do (see design doc section B-2) --
  # these two products' reading screens are reachable directly (bookmarks,
  # search results, shared links), so "동작 완전히 동일 유지" extends to what
  # URL clicking around inside the reader itself lands on, not just the
  # entry point. A product with no legacy route falls back to the generic
  # helper, which is the only path it's ever had.
  def product_content_index_path_for(product_code)
    case product_code
    when "chatdox" then docs_path
    when "claudox" then claudox_read_path
    else product_content_index_path(product_code)
    end
  end

  def product_chapter_path_for(product_code, id)
    case product_code
    when "chatdox" then doc_path(id)
    when "claudox" then claudox_chapter_path(id)
    else product_chapter_path(product_code, id)
    end
  end

  def locked_chapter_redirect_path
    path = @product&.landing_page_path
    return root_path if path.blank?

    "#{path}#pricing"
  end

  def strip_leading_heading(raw_markdown)
    raw_markdown.sub(/\A\s*#[^\n]*\n?/, "")
  end

  def chapter_file_path(slug)
    @source.path.children.find do |candidate|
      candidate.file? && candidate.extname == ".md" && candidate.basename(".md").to_s == slug
    end
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
