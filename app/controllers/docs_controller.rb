class DocsController < ApplicationController
  include ChapterImages

  DOCS_PATH = Curriculum::DOCS_PATH

  def index
    @chapters = chapters_with_availability
    @phase_chapters = chapters_by_phase(@chapters)
  end

  def image
    serve_chapter_image(DOCS_PATH.join("images"), params[:filename])
  end

  def show
    request.format = :html

    @chapters = chapters_with_availability
    @phase_chapters = chapters_by_phase(@chapters)
    @current_id = params[:id].to_s.rjust(2, "0")
    @current_chapter = Curriculum.find(@current_id)&.merge(product_code: "chatdox")

    unless @current_chapter
      render plain: "챕터를 찾을 수 없습니다.", status: :not_found
      return
    end

    authorize @current_chapter, :view?, policy_class: DocPolicy

    file_path = case @current_id
    when "01" then DOCS_PATH.join("01_overview.md")
    when "02" then DOCS_PATH.join("02_rails_basics.md")
    when "03" then DOCS_PATH.join("03_dev_setup.md")
    when "04" then DOCS_PATH.join("04_landing_page.md")
    when "05" then DOCS_PATH.join("05_project_structure.md")
    when "06" then DOCS_PATH.join("06_database.md")
    when "07" then DOCS_PATH.join("07_authentication.md")
    when "08" then DOCS_PATH.join("08_authorization.md")
    when "09" then DOCS_PATH.join("09_payment.md")
    when "10" then DOCS_PATH.join("10_dashboard.md")
    when "11" then DOCS_PATH.join("11_admin.md")
    when "12" then DOCS_PATH.join("12_email.md")
    when "13" then DOCS_PATH.join("13_file_upload.md")
    when "14" then DOCS_PATH.join("14_api.md")
    when "15" then DOCS_PATH.join("15_testing.md")
    when "16" then DOCS_PATH.join("16_performance.md")
    when "17" then DOCS_PATH.join("17_security.md")
    when "18" then DOCS_PATH.join("18_deployment.md")
    when "19" then DOCS_PATH.join("19_monitoring.md")
    when "20" then DOCS_PATH.join("20_launch.md")
    end
    unless file_path && File.exist?(file_path)
      render plain: "아직 공개되지 않은 챕터입니다.", status: :not_found
      return
    end

    @last_updated_at = Curriculum.last_updated_at(@current_chapter[:slug])
    raw_markdown = File.read(file_path)
    @chapter_progress = if user_signed_in?
      current_user.chapter_progresses.find_by(chapter_id: @current_id, product_code: "chatdox")
    end

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

    @content_html = markdown.render(raw_markdown).html_safe
    render :show, formats: :html
  end

  private

  def chapters_with_availability
    Curriculum.all.map do |chapter|
      file_path = DOCS_PATH.join("#{chapter[:slug]}.md")
      product_chapter = chapter.merge(product_code: "chatdox")
      product_chapter.merge(
        available: File.exist?(file_path),
        accessible: DocPolicy.new(current_user, product_chapter).view?
      )
    end
  end

  def chapters_by_phase(chapters)
    Curriculum.phases.map do |phase|
      phase_chapters = chapters.select { |chapter| phase[:range].cover?(chapter[:id].to_i) }
      available_count = phase_chapters.count { |chapter| chapter[:available] }

      phase.merge(
        chapters: phase_chapters,
        available_count: available_count,
        total_count: phase_chapters.size
      )
    end
  end
end
