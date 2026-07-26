class RefsController < ApplicationController
  REFS_PATH = Rails.root.join("refs")

  REFERENCES = [
    { id: "payment-00_overview", chapter_id: "09", slug: "payment/00_overview", title: "PortOne 결제 시스템" },
    { id: "payment-01_setup", chapter_id: "09", slug: "payment/01_setup", title: "환경 설정" },
    { id: "payment-02_implementation", chapter_id: "09", slug: "payment/02_implementation", title: "구현 상세" },
    { id: "payment-03_troubleshooting", chapter_id: "09", slug: "payment/03_troubleshooting", title: "문제 해결" },
    { id: "payment-04_testing", chapter_id: "09", slug: "payment/04_testing", title: "토스 테스트 결과" },
    { id: "payment-04_testing_portone", chapter_id: "09", slug: "payment/04_testing_portone", title: "PortOne 결제 테스트 가이드" }
  ].freeze

  before_action :require_admin!

  def index
    @references = references_with_metadata
    @phase_refs = refs_by_phase(@references)
  end

  def show
    @references = references_with_metadata
    @phase_refs = refs_by_phase(@references)
    @current_ref = @references.find { |reference| reference[:id] == params[:id] }

    unless @current_ref
      redirect_to refs_path, alert: "참조 문서를 찾을 수 없습니다."
      return
    end

    doc_path = REFS_PATH.join("#{@current_ref[:slug]}.md")
    unless File.exist?(doc_path)
      redirect_to refs_path, alert: "참조 문서 파일을 찾을 수 없습니다."
      return
    end

    @content_html = render_markdown(File.read(doc_path))
    @available_references = @references.select { |reference| reference[:available] }
    @current_index = @available_references.find_index { |reference| reference[:id] == @current_ref[:id] }
    @prev_ref = @current_index&.positive? ? @available_references[@current_index - 1] : nil
    @next_ref = @current_index && @current_index < @available_references.length - 1 ? @available_references[@current_index + 1] : nil
  end

  private

  def require_admin!
    return if current_user&.admin?

    redirect_to root_path, alert: "권한이 없습니다."
  end

  def references_with_metadata
    REFERENCES.map do |reference|
      chapter = ProductContent.for("chatdox").find(reference[:chapter_id])
      reference.merge(
        chapter: chapter,
        available: File.exist?(REFS_PATH.join("#{reference[:slug]}.md"))
      )
    end
  end

  def refs_by_phase(references)
    ProductContent.for("chatdox").phases.map do |phase|
      phase_refs = references.select { |reference| phase[:range].cover?(reference[:chapter_id].to_i) }
      available_count = phase_refs.count { |reference| reference[:available] }

      phase.merge(
        references: phase_refs,
        available_count: available_count,
        total_count: phase_refs.size
      )
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

    helpers.sanitize(
      markdown.render(raw_markdown),
      tags: %w[
        h1 h2 h3 h4 h5 h6 p br hr ul ol li pre code blockquote strong em a
        table thead tbody tr th td
      ],
      attributes: %w[href target rel]
    )
  end
end
