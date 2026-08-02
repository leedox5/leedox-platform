class ChatdoxContentController < ApplicationController
  IMAGE_MIME_TYPES = {
    ".gif" => "image/gif",
    ".jpeg" => "image/jpeg",
    ".jpg" => "image/jpeg",
    ".png" => "image/png",
    ".webp" => "image/webp"
  }.freeze

  before_action :load_source

  def season
    @season = source.seasons.find { |candidate| candidate[:code] == params[:season_code] }
    return render_not_found unless @season && %i[publishing completed upcoming].include?(@season[:status])

    @chapters = source.public_chapters.select { |chapter| chapter[:season_code] == @season[:code] }
    @summary = ProductContent::ProgressSummary.call(user: current_user, source:)
    @season_summary = @summary.season(@season[:code])
  end

  def episode
    @chapter = source.find_direct(canonical_id)
    return render_not_found unless @chapter

    decision = SeasonChapterAccessPolicy.new(user: current_user, chapter: @chapter, context: :direct).decision
    return handle_denied(decision.reason) unless decision.allowed?

    body_path = source.body_path(@chapter, context: @chapter[:status] == :archived ? :direct : :public)
    return render_not_found unless body_path

    @summary = ProductContent::ProgressSummary.call(user: current_user, source:)
    @season_summary = @summary.season(@chapter[:season_code])
    @public_season_chapters = source.public_chapters.select { |chapter| chapter[:season_code] == @chapter[:season_code] }
    @chapter_progress = if current_user
      ChapterProgress.for_chapter(
        user: current_user, product_code: "chatdox", chapter_id: @chapter[:id], source:
      ).completed.first
    end
    @archived = @chapter[:status] == :archived
    @content_html = render_markdown(body_path.read)
    @last_updated_at = snapshot_generated_at
  end

  def image
    path = source.image_path(season_code: params[:season_code], relative_path: params[:filename], context: :public)
    return render_not_found unless path

    send_safe_image(path, public_cache: true)
  end

  def archived_image
    chapter = source.find_direct(canonical_id)
    decision = SeasonChapterAccessPolicy.new(user: current_user, chapter:, context: :direct).decision
    return render_not_found unless decision.allowed? && chapter[:status] == :archived

    path = source.image_path(season_code: params[:season_code], relative_path: params[:filename], context: :direct)
    return render_not_found unless path

    send_safe_image(path, public_cache: false)
  end

  private

  attr_reader :source

  def load_source
    @source = ProductContent.seasoned_chatdox
    render_unavailable unless source.usable?
  end

  def canonical_id
    "#{params[:season_code].upcase}E#{params[:episode_number]}"
  end

  def handle_denied(reason)
    case reason
    when :authentication_required
      redirect_to new_user_session_path(redirect_to: request.path), alert: "로그인 후 이용 가능합니다."
    when :trial_required, :license_required
      @access_reason = reason
      render :access_required, status: :forbidden
    when :invalid_snapshot
      render_unavailable
    else
      render_not_found
    end
  end

  def render_not_found
    render plain: "콘텐츠를 찾을 수 없습니다.", status: :not_found
  end

  def render_unavailable
    render plain: "콘텐츠를 일시적으로 불러올 수 없습니다.", status: :service_unavailable
  end

  def render_markdown(raw_markdown)
    renderer = Redcarpet::Render::HTML.new(
      hard_wrap: true,
      link_attributes: { target: "_blank", rel: "noopener noreferrer" }
    )
    markdown = Redcarpet::Markdown.new(
      renderer, autolink: true, tables: true, fenced_code_blocks: true,
      strikethrough: true, superscript: true
    )
    html = markdown.render(raw_markdown.sub(/\A\s*#[^\n]*\n?/, ""))
    rewrite_public_images(html).html_safe
  end

  def rewrite_public_images(html)
    html.gsub(%r{(<img\s+[^>]*src=")/docs/images/([^"?]+)(")}) do
      path = if @archived
        archived_chatdox_episode_image_path(
          @chapter[:season_code], @chapter[:display_number], $2
        )
      else
        chatdox_season_image_path(@chapter[:season_code], $2)
      end
      "#{$1}#{path}#{$3}"
    end
  end

  def snapshot_generated_at
    Time.zone.parse(source.snapshot.build_metadata.fetch("generated_at"))
  rescue ArgumentError, KeyError
    nil
  end

  def send_safe_image(path, public_cache:)
    mime = IMAGE_MIME_TYPES[path.extname.downcase]
    return render_not_found unless mime

    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Cache-Control"] = public_cache ? "public, max-age=31536000, immutable" : "private, no-store"
    send_file path, type: mime, disposition: "inline"
  end
end
