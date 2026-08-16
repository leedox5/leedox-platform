# Redcarpet::Render::HTML has no Ruby-level default implementation of `link`
# to call via `super` -- the C extension only invokes a Ruby `link` method at
# all when one is defined, and otherwise renders the tag itself internally.
# So once we override `link` here, we're responsible for the full <a> output
# for every link, not just the ones we rewrite.
#
# HQ's markdown authors write plain GitHub-relative links to other .md files
# in the same folder (they resolve fine on GitHub). This site only serves
# registered chapters, so such a link has nowhere to land unless its target
# happens to match a real chapter's slug. Handoff 0049: resolve it to that
# chapter's URL when a match exists, otherwise drop the link and keep the
# text so the sentence still reads naturally.
class ProductContent::LinkRewritingRenderer < Redcarpet::Render::HTML
  include Rails.application.routes.url_helpers

  # Anything NOT external (http(s)://), NOT a site-absolute path (/...), and
  # NOT anchor-only (#...) is a relative link. Only .md targets are ours to
  # touch -- everything else (images, other file types) renders unchanged.
  RELATIVE_MD_LINK = %r{\A(?!https?://)(?!/)(?!\#)(?<path>[^\#]+)\.md(?<anchor>\#.+)?\z}i

  def initialize(product_code:, chapters:, link_attributes: {}, **options)
    super(link_attributes: link_attributes, **options)
    @product_code = product_code
    @chapters = chapters
    @link_attributes = link_attributes
  end

  def link(link_target, title, content)
    match = RELATIVE_MD_LINK.match(link_target.to_s)
    return render_link(link_target, title, content) unless match

    chapter = @chapters.find { |c| c[:slug] == File.basename(match[:path]) }
    return content unless chapter

    render_link("#{chapter_path(chapter[:id])}#{match[:anchor]}", title, content)
  end

  private

  # Mirrors ProductContentController#product_chapter_path_for -- Chatdox and
  # Claudox keep their own legacy reader URLs, everything else uses the
  # generic /content/:product_code/:id route.
  def chapter_path(id)
    case @product_code
    when "chatdox" then doc_path(id)
    when "claudox" then claudox_chapter_path(id)
    else product_chapter_path(@product_code, id)
    end
  end

  def render_link(href, title, content)
    attrs = +%(href="#{ERB::Util.html_escape(href)}")
    attrs << %( title="#{ERB::Util.html_escape(title)}") if title.present?
    @link_attributes.each { |name, value| attrs << %( #{name}="#{ERB::Util.html_escape(value)}") }
    "<a #{attrs}>#{content}</a>"
  end
end
