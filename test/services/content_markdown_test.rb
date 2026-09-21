require "test_helper"

# Handoff 0063 -- the shared, restricted Markdown renderer. The security rules
# (no raw HTML, no external images, no style attribute) are the point of this
# file: each is checked against the rendered result, not just the input.
class ContentMarkdownTest < ActiveSupport::TestCase
  setup do
    @line = ProductLine.create!(internal_name: "A", customer_name: "제품", slug: "md-line", introduction: "소개", status: "published")
    @season = @line.product_seasons.create!(internal_name: "S", season_code: "S01", slug: "s01", status: "published", visibility: "public")
    @episode = @season.content_episodes.create!(position: 1, customer_title: "편", body: "본문", status: "published")
  end

  def image_for(parent, alt: "설명", fixture: "covers/cover.jpg", type: "image/jpeg")
    parent.content_images.create!(alt: alt, file: { io: file_fixture(fixture).open, filename: File.basename(fixture), content_type: type })
  end

  # Same approach as the cover tests: swap a class method for the block's duration.
  def with_class_method(klass, name, value)
    original = klass.method(name)
    klass.define_singleton_method(name) { |*| value }
    yield
  ensure
    klass.define_singleton_method(name, original)
  end

  def render_html(text, **options)
    Nokogiri::HTML5.fragment(ContentMarkdown.render(text, **options))
  end

  # --- raw HTML is never passed through -------------------------------------

  test "raw HTML is shown as text and never becomes an element" do
    html = render_html(%(<script>alert(1)</script>\n\n<iframe src="//evil.example"></iframe>\n\n<img src=x onerror=alert(1)>\n\n<b>굵게</b>))

    %w[script iframe img b].each { |tag| assert_empty html.css(tag), "<#{tag}> must not be rendered" }
    assert_includes html.text, "<script>alert(1)</script>"
    assert_includes html.text, "<b>굵게</b>"
  end

  test "there is no style attribute anywhere, whether typed as HTML or produced by the renderer" do
    html = render_html(%(<p style="position:fixed;top:0">x</p>\n\n- [ ] 할 일\n- [x] 끝\n\n[링크](https://example.com)))

    assert_empty html.css("[style]")
    assert_not_includes ContentMarkdown::ALLOWED_ATTRIBUTES, "style"
  end

  test "javascript: and data: links do not become links" do
    html = render_html("[a](javascript:alert(1)) [b](data:text/html;base64,PHNjcmlwdD4=) [c](vbscript:x)")

    assert_empty html.css("a")
    assert_includes html.text, "javascript:alert(1)"
  end

  test "an <input> that is not a checkbox typed as HTML is only text" do
    html = render_html(%(<input type="text" value="x">))

    assert_empty html.css("input")
    assert_includes html.text, %(<input type="text")
  end

  # --- images ---------------------------------------------------------------

  test "external image URLs render nothing and are reported" do
    [ "https://evil.example/t.png", "http://evil.example/t.png", "//evil.example/t.png", "data:image/png;base64,AAAA", "/product-images/abc", "/etc/passwd.png" ].each do |url|
      result = ContentMarkdown.render_with_warnings("앞 ![외부](#{url}) 뒤", parent: @line)
      html = Nokogiri::HTML5.fragment(result.html)

      assert_empty html.css("img"), "#{url} must not render an image"
      assert_equal 1, result.warnings.size, "#{url} should be reported"
    end
  end

  test "an image of the record itself renders as our own image path with the stored alt text" do
    image = image_for(@line, alt: "화면 캡처")

    html = render_html("![](#{image.reference})", parent: @line, profile: :marketing)
    img = html.at_css("img")
    assert_equal "/product-images/#{image.public_id}", img["src"]
    assert_equal "화면 캡처", img["alt"]
    assert_equal "lazy", img["loading"]
    assert_equal %w[alt loading src], img.attribute_nodes.map(&:name).sort
  end

  test "the alt text written in the Markdown wins over the stored one" do
    image = image_for(@line, alt: "저장된 설명")
    assert_equal "글 안의 설명", render_html("![글 안의 설명](#{image.reference})", parent: @line).at_css("img")["alt"]
  end

  test "the admin preview points the same image at the admin-only route" do
    image = image_for(@episode)
    img = render_html("![x](#{image.reference})", parent: @episode, admin: true).at_css("img")

    assert_equal "/admin/content_images/#{image.public_id}/body", img["src"]
  end

  test "an image of another record, a deleted image and an unknown id render nothing" do
    others = image_for(@episode)
    other_line = ProductLine.create!(internal_name: "B", customer_name: "다른", slug: "other-md", introduction: "소개")
    other_lines_image = image_for(other_line)
    unknown = "image:11111111-1111-1111-1111-111111111111"

    [ others.reference, other_lines_image.reference, unknown ].each do |reference|
      result = ContentMarkdown.render_with_warnings("![x](#{reference})", parent: @line)
      assert_empty Nokogiri::HTML5.fragment(result.html).css("img"), "#{reference} must not render on this product line"
      assert_equal 1, result.warnings.size
    end
    # ...but the episode's own image does render on the episode
    assert render_html("![x](#{others.reference})", parent: @episode).at_css("img")
  end

  test "an <img> tag typed as HTML pointing at our own image path is still only text" do
    image = image_for(@line)
    html = render_html(%(<img src="/product-images/#{image.public_id}" alt="raw">), parent: @line)

    assert_empty html.css("img")
  end

  test "a text with no image reference never touches the images table, and a missing table is harmless" do
    with_class_method(ContentImage, :table_exists?, false) do
      html = render_html("![x](image:11111111-1111-1111-1111-111111111111)", parent: @line)
      assert_empty html.css("img")
    end
    assert_equal({}, ContentMarkdown.referenced_images("그냥 글", @line))
  end

  # --- the structural pass holds even if an earlier layer were bypassed ------

  test "the final pass strips anything unsafe from HTML that got past the earlier layers" do
    dirty = %(<img src="https://evil.example/t.png"><img src="/product-images/ok" onerror="x()" width="9">) +
            %(<input type="text" value="x"><input type="checkbox" checked name="n" onclick="x()">) +
            %(<a href="https://example.com" onclick="x()" class="evil" target="_self">a</a>) +
            %(<a href="/relative" target="_blank">b</a><p class="evil" style="x">p</p>) +
            %(<code class="ruby">c</code><code class="a b">d</code><ul><li class="checklist-item">ok</li><li class="other">no</li></ul>)

    html = Nokogiri::HTML5.fragment(ContentMarkdown.send(:finalize, dirty))

    assert_equal [ "/product-images/ok" ], html.css("img").map { |img| img["src"] }
    assert_empty(html.at_css("img").attribute_nodes.map(&:name) - %w[src alt title loading])
    assert_equal 1, html.css("input").size
    checkbox = html.at_css("input")
    assert_equal %w[checked disabled type], checkbox.attribute_nodes.map(&:name).sort
    external, relative = html.css("a").to_a
    assert_equal "_blank", external["target"]
    assert_nil relative["target"]
    assert_equal "noopener noreferrer nofollow", external["rel"]
    assert_nil external["class"]
    assert_nil html.at_css("p")["class"]
    assert_equal "ruby", html.css("code").first["class"]
    assert_nil html.css("code").last["class"]
    assert_equal "checklist-item", html.css("li").first["class"]
    assert_nil html.css("li").last["class"]
  end

  # --- what it should still do ----------------------------------------------

  test "links get rel and open externally in a new tab; relative links stay in place" do
    html = render_html("[밖](https://example.com/a) [안](/docs)")
    outside, inside = html.css("a").to_a

    assert_equal "noopener noreferrer nofollow", outside["rel"]
    assert_equal "_blank", outside["target"]
    assert_equal "noopener noreferrer nofollow", inside["rel"]
    assert_nil inside["target"]
  end

  test "checklists become disabled checkboxes marked by a class" do
    html = render_html("- [ ] 하나\n- [x] 둘\n- 일반")
    items = html.css("li")

    assert_equal %w[checklist-item checklist-item], items.first(2).map { |li| li["class"] }
    assert_nil items.last["class"]
    assert_equal 2, html.css("input[type=checkbox][disabled]").size
    assert_equal 1, html.css("input[checked]").size
  end

  test "tables, code blocks, quotes, strikethrough and superscript render" do
    html = render_html("| a | b |\n|---|---|\n| 1 | 2 |\n\n```ruby\nputs 1\n```\n\n> 인용\n\n~~지움~~ x^2")

    assert html.at_css("table th")
    assert_equal "ruby", html.at_css("pre code")["class"]
    assert html.at_css("blockquote")
    assert html.at_css("del")
    assert html.at_css("sup")
  end

  test "the marketing profile keeps a single line break; the episode profile does not" do
    assert_includes ContentMarkdown.render("줄1\n줄2", profile: :marketing), "<br>"
    assert_not_includes ContentMarkdown.render("줄1\n줄2", profile: :episode), "<br>"
  end

  test "nil and blank text render as an empty string, and the result is html_safe" do
    assert_equal "", ContentMarkdown.render(nil).to_s.strip
    assert_predicate ContentMarkdown.render("**x**"), :html_safe?
  end
end
