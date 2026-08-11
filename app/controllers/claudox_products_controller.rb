class ClaudoxProductsController < ApplicationController
  def show
    source = ProductContent.for("claudox")
    # This page's "실제 구성과 목차" section only ever showed the regular
    # 1..20 chapter list (the "X / 20" count is hardcoded to that scope in
    # the view) -- appendix chapters (90..99) belong to the reader-facing
    # content list, not this marketing summary, so they're excluded here.
    @chapters = source.chapters.select { |chapter| chapter[:kind] == :chapter }.map do |chapter|
      chapter.merge(complete: source.editorial_status(chapter[:id]) == :written)
    end

    # Real bonus content (90..99, minus non_chapter_files like 97_commands.md)
    # -- excluded from the "완성 X / 20" count on purpose (handoff 0044's own
    # instruction not to touch that), but still real, license-gated chapters
    # a buyer can read, so the page should at least say they exist.
    @appendix_chapters = source.chapters.select { |chapter| chapter[:kind] == :appendix }.map do |chapter|
      chapter.merge(
        # HQ's source markdown H1s carry their own "부록. " prefix (see
        # ProductContent::FilesystemSource#extract_title's equivalent comment
        # for the numbered-chapter case) -- the list already labels each card
        # "부록 NN", so showing it again from the title would read "부록 90 /
        # 부록. 제목" (0044 R2-1). Display-only: the source .md files and the
        # chapter reader's own title rendering are untouched. .sub is a no-op
        # if a title ever arrives without the prefix.
        title: chapter[:title].sub(/\A부록\.\s*/, ""),
        # Same accessibility check the real reader gate uses (DocPolicy), not
        # a new one -- 0044 R1 accidentally showed 🔒 unconditionally, which
        # is exactly the "display and gate disagree" failure backlog 0019
        # was about (0044 R2-2).
        accessible: DocPolicy.new(current_user, chapter).view?
      )
    end

    # Sample count must track the same guest_chapter_limit the actual guest
    # gate (DocPolicy) and the hero badge below both read from -- not a bare
    # number -- so this can never again drift out of sync with what a guest
    # can actually open (handoff 0036's conclusion, reapplied here).
    @featured_chapters = @chapters.select { |chapter| chapter[:complete] }.first(source.guest_chapter_limit)
  end
end
