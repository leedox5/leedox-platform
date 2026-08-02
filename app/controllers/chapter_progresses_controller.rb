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

    ChapterProgress.uncomplete!(
      user: current_user,
      product_code: chapter[:product_code],
      chapter_id: chapter[:canonical_id] || chapter[:id],
      source: ProductContent.for(chapter[:product_code])
    )

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

    # Same reasoning for :available -- ChatdoxLegacySource can list a chapter
    # that's in the fixed 20-chapter table but has no file written yet
    # (available: false); the reading screen 404s on it, so the "complete"
    # button never renders for it either. A crafted request could otherwise
    # mark an unwritten chapter as completed. FilesystemSource-backed
    # products never hit this branch -- their chapters list only ever
    # contains files that actually exist, so available is always true there.
    return nil unless chapter&.dig(:available)

    chapter
  end

  def redirect_path(chapter)
    product_chapter_path(chapter[:product_code], chapter[:id])
  end

  def complete_chapter_progress(chapter)
    ChapterProgress.complete!(
      user: current_user,
      product_code: chapter[:product_code],
      chapter_id: chapter[:canonical_id] || chapter[:id],
      source: ProductContent.for(chapter[:product_code])
    )
  end
end
