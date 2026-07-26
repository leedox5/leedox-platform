class Admin::ContentProgressController < Admin::BaseController
  CLAUDOX_PATH = Rails.root.join("hq/claudox")
  CLAUDOX_PROGRESS_PATH = CLAUDOX_PATH.join("88_progress.md")
  CLAUDOX_ROW_PATTERN = /^\|\s*\d+\s*\|\s*(.+?)\s*\|\s*\[.+?\]\((\d{2})_[a-z0-9_]+\.md\)\s*\|\s*\d+%\s*\|\s*(✅|⬜|🟡)\s*\|$/

  def show
    chatdox_source = ProductContent.for("chatdox")
    @chatdox_chapters = chatdox_source.chapters.map do |chapter|
      {
        id: chapter[:id],
        title: chapter[:title],
        done: chapter[:available],
        path: doc_path(chapter[:id])
      }
    end
    @chatdox_done_count = @chatdox_chapters.count { |chapter| chapter[:done] }
    @chatdox_percent = percent(@chatdox_done_count, @chatdox_chapters.size)
    @chatdox_phases = group_by_phase(@chatdox_chapters, chatdox_source.phases)

    # Claudox's writing-progress table (88_progress.md, qualitative %/✅⬜🟡)
    # predates this migration and carries information ProductContent's
    # editorial_status doesn't (a human-curated completeness percentage, not
    # just written/draft) -- left as its own parser rather than forced into
    # the generic interface. See leedox_multi_product_platform_stage3_migration_r1
    # result.md and docs/internal/content_platform_design.md section A-3.
    @claudox_chapters = parse_claudox_progress
    @claudox_done_count = @claudox_chapters.count { |chapter| chapter[:done] }
    @claudox_percent = percent(@claudox_done_count, @claudox_chapters.size)
    @claudox_phases = group_by_phase(@claudox_chapters, ProductContent.for("claudox").phases)
  end

  private

  def parse_claudox_progress
    return [] unless File.exist?(CLAUDOX_PROGRESS_PATH)

    File.read(CLAUDOX_PROGRESS_PATH).scan(CLAUDOX_ROW_PATTERN).map do |title, id, status|
      { id: id, title: title, done: status == "✅", path: claudox_chapter_path(id) }
    end
  end

  def group_by_phase(chapters, phases)
    phases.map do |phase|
      phase_chapters = chapters.select { |chapter| phase[:range].cover?(chapter[:id].to_i) }
      phase.merge(chapters: phase_chapters, done_count: phase_chapters.count { |chapter| chapter[:done] })
    end
  end

  def percent(done, total)
    return 0 if total.zero?

    ((done.to_f / total) * 100).round
  end
end
