class ChapterProgressesController < ApplicationController
  before_action :authenticate_user!

  def create
    chapter = find_chapter
    return head :not_found unless chapter

    authorize chapter, :view?, policy_class: DocPolicy

    complete_chapter_progress(chapter)

    redirect_to redirect_path(chapter), notice: "완료한 챕터로 표시했습니다."
  end

  def destroy
    chapter = find_chapter
    return head :not_found unless chapter

    authorize chapter, :view?, policy_class: DocPolicy

    current_user.chapter_progresses.find_by(chapter_id: chapter[:id], product_code: chapter[:product_code])&.destroy!

    redirect_to redirect_path(chapter), notice: "완료 표시를 취소했습니다."
  end

  private

  def find_chapter
    product_code = params[:product_code].presence || "chatdox"
    chapter = ProductContent.for(product_code).find(params[:chapter_id])

    # Appendix chapters are excluded from progress tracking -- the UI never
    # renders the button, but without this check a crafted request would
    # still reach ChapterProgress#update!, which rejects chapter_id outside
    # 1..20 via a validation error (an unhandled 500, not a clean 404).
    return nil if chapter&.dig(:kind) == :appendix

    chapter
  end

  def redirect_path(chapter)
    product_chapter_path(chapter[:product_code], chapter[:id])
  end

  def complete_chapter_progress(chapter)
    progress = current_user.chapter_progresses.find_or_initialize_by(
      chapter_id: chapter[:id], product_code: chapter[:product_code]
    )
    progress.update!(completed_at: Time.current)
  rescue ActiveRecord::RecordNotUnique
    current_user.chapter_progresses
      .find_by!(chapter_id: chapter[:id], product_code: chapter[:product_code])
      .update!(completed_at: Time.current)
  end
end
