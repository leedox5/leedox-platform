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

    @featured_chapters = @chapters.select { |chapter| chapter[:complete] }.first(3)
  end
end
