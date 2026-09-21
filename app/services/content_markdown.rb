# The one Markdown renderer for database-authored content -- a ProductLine
# introduction and a ContentEpisode body/takeaway (handoff 0063). It replaces the
# three copies that had drifted apart (ProductLinesController,
# ProductContentController#render_bundle_markdown and the admin preview).
#
# The legacy file-based products keep their own renderer
# (ProductContentController#render_markdown with LinkRewritingRenderer) on
# purpose; nothing here touches it.
#
# What it guarantees (each layer is independent, so one slip is not enough):
#   1. Redcarpet: raw HTML in the text is *escaped*, never passed through
#      (`escape_html`), and only http/https/ftp/mailto/relative links are kept
#      (`safe_links_only`).
#   2. An image is rendered only for `![alt](image:<public_id>)` that names an
#      image of the record being rendered (`parent`). An external URL, a data:
#      URI, an unknown id, or another record's image renders nothing (and is
#      reported in `warnings` for the admin preview).
#   3. Rails' safe-list sanitizer with a fixed tag/attribute list -- no `style`.
#   4. A structural pass over the result: only our two image URL prefixes may
#      appear in `<img src>`, only a disabled checkbox `<input>` survives,
#      every link gets rel="noopener noreferrer nofollow", and `class` is kept
#      only where this renderer itself puts one.
#
# The returned string is already safe HTML (html_safe); views print it directly.
module ContentMarkdown
  # `hard_wrap` keeps a single line break as a line break. The introduction
  # needs it: 0060 stored plain text whose line breaks must keep showing exactly
  # as before. Episodes keep the paragraph-style behavior they always had.
  PROFILES = {
    marketing: { hard_wrap: true },
    episode: { hard_wrap: false }
  }.freeze

  ALLOWED_TAGS = %w[h1 h2 h3 h4 h5 h6 p br hr ul ol li pre code blockquote strong em del sup a img table thead tbody tr th td input].freeze
  ALLOWED_ATTRIBUTES = %w[href rel target src alt title type disabled checked class].freeze

  IMAGE_REFERENCE = /\Aimage:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\z/i
  EXTENSIONS = { autolink: true, tables: true, fenced_code_blocks: true, strikethrough: true, superscript: true }.freeze

  CUSTOMER_IMAGE_PREFIX = "/product-images/".freeze
  ADMIN_IMAGE_PREFIX = "/admin/content_images/".freeze
  CHECKLIST_CLASS = "checklist-item".freeze

  Result = Struct.new(:html, :warnings)

  # Redcarpet's own image rendering would emit any URL it is given.
  class Renderer < Redcarpet::Render::HTML
    attr_accessor :images, :admin, :warnings

    def image(link, _title, alt_text)
      reference = link.to_s.match(IMAGE_REFERENCE)
      image = reference && images[reference[1].downcase]
      unless image
        warnings << image_warning(link)
        return ""
      end

      alt = alt_text.to_s.strip.presence || image.alt
      %(<img src="#{ERB::Util.html_escape(image_path(image))}" alt="#{ERB::Util.html_escape(alt)}">)
    end

    private

    def image_path(image)
      routes = Rails.application.routes.url_helpers
      admin ? routes.admin_content_image_file_path(image.public_id, variant: "body") : routes.product_image_path(image.public_id)
    end

    def image_warning(link)
      if link.to_s.match?(%r{\A(?:[a-z][a-z0-9+.-]*:)?//}i) || link.to_s.match?(/\A(?:https?|data|ftp):/i)
        "외부 이미지는 사용할 수 없어 표시하지 않았습니다: #{link.to_s.truncate(80)}"
      elsif link.to_s.start_with?("image:")
        "이 글에 속하지 않았거나 삭제된 이미지라 표시하지 않았습니다: #{link.to_s.truncate(80)}"
      else
        "이미지는 ![대체문구](image:이미지ID) 형식으로만 넣을 수 있어 표시하지 않았습니다: #{link.to_s.truncate(80)}"
      end
    end
  end

  def self.render(text, parent: nil, profile: :episode, admin: false)
    render_with_warnings(text, parent: parent, profile: profile, admin: admin).html
  end

  def self.render_with_warnings(text, parent: nil, profile: :episode, admin: false)
    options = PROFILES.fetch(profile)
    renderer = Renderer.new(escape_html: true, safe_links_only: true, hard_wrap: options[:hard_wrap],
                            link_attributes: { rel: "noopener noreferrer nofollow" })
    renderer.images = referenced_images(text, parent)
    renderer.admin = admin
    renderer.warnings = []

    html = Redcarpet::Markdown.new(renderer, **EXTENSIONS).render(text.to_s)
    html = checklist_items(html)
    html = sanitizer.sanitize(html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES).to_s
    Result.new(finalize(html), renderer.warnings.uniq)
  end

  # Only the images this text actually names, and only the parent's own. Nothing
  # is queried unless the text contains a reference, so rendering an ordinary
  # text never touches the table (which matters between a deploy and its
  # migration).
  def self.referenced_images(text, parent)
    return {} if parent.nil? || !text.to_s.include?("image:") || !ContentImage.table_exists?

    ids = text.to_s.scan(/image:([0-9a-f-]{36})/i).flatten.map(&:downcase).uniq
    return {} if ids.empty?

    parent.content_images.where(public_id: ids).with_attached_file.index_by(&:public_id)
  end

  # "- [ ] foo" / "- [x] foo": Redcarpet has no task-list support, so it emits
  # literal "[ ]". Turned into a disabled checkbox; the list-item look comes from
  # the `.checklist-item` CSS class, not an inline style (styles are not allowed).
  def self.checklist_items(html)
    html.gsub(/<li>\[([ xX])\]\s*/) do
      checked = Regexp.last_match(1).strip.casecmp?("x") ? " checked" : ""
      %(<li class="#{CHECKLIST_CLASS}"><input type="checkbox" disabled#{checked}> )
    end
  end

  def self.sanitizer
    @sanitizer ||= Rails::HTML5::SafeListSanitizer.new
  end

  def self.finalize(html)
    fragment = Nokogiri::HTML5.fragment(html)

    fragment.css("img").each do |img|
      unless img["src"].to_s.start_with?(CUSTOMER_IMAGE_PREFIX, ADMIN_IMAGE_PREFIX)
        img.remove
        next
      end

      keep = %w[src alt title]
      img.attribute_nodes.each { |attribute| attribute.remove unless keep.include?(attribute.name) }
      img["loading"] = "lazy"
    end

    fragment.css("input").each do |input|
      if input["type"] == "checkbox"
        checked = input.key?("checked")
        input.attribute_nodes.each(&:remove)
        input["type"] = "checkbox"
        input["disabled"] = "disabled"
        input["checked"] = "checked" if checked
      else
        input.remove
      end
    end

    fragment.css("a").each do |link|
      link["rel"] = "noopener noreferrer nofollow"
      external = link["href"].to_s.match?(/\Ahttps?:/i)
      external ? link["target"] = "_blank" : link.remove_attribute("target")
    end

    fragment.css("[class]").each do |node|
      value = node["class"].to_s
      allowed = (node.name == "li" && value == CHECKLIST_CLASS) || (node.name == "code" && value.match?(/\A[\w+#.-]{1,30}\z/))
      node.remove_attribute("class") unless allowed
    end

    fragment.to_html.html_safe
  end
  private_class_method :finalize, :checklist_items, :sanitizer
end
