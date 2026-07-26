require "test_helper"

class ChapterImagesTest < ActionDispatch::IntegrationTest
  FIXTURE_IMAGE = Rails.root.join("test/fixtures/files/chapter_image_test.png")

  setup do
    @docs_images_dir = ProductContent.for("chatdox").images_path
    @claudox_images_dir = ProductContent.for("claudox").images_path
    @filename = "#{SecureRandom.hex(8)}.png"

    FileUtils.mkdir_p(@docs_images_dir)
    FileUtils.mkdir_p(@claudox_images_dir)
    FileUtils.cp(FIXTURE_IMAGE, @docs_images_dir.join(@filename))
    FileUtils.cp(FIXTURE_IMAGE, @claudox_images_dir.join(@filename))
  end

  teardown do
    FileUtils.rm_f(@docs_images_dir.join(@filename))
    FileUtils.rm_f(@claudox_images_dir.join(@filename))
  end

  test "serves an existing docs chapter image" do
    get "/docs/images/#{@filename}"

    assert_response :success
    assert_equal "image/png", response.media_type
  end

  test "serves an existing claudox chapter image" do
    get "/claudox/images/#{@filename}"

    assert_response :success
    assert_equal "image/png", response.media_type
  end

  test "returns 404 for a missing docs image" do
    get "/docs/images/does-not-exist.png"

    assert_response :not_found
  end

  test "returns 404 for a missing claudox image" do
    get "/claudox/images/does-not-exist.png"

    assert_response :not_found
  end

  test "blocks path traversal out of the docs images directory" do
    # Gemfile definitely exists at the repo root, so this proves the containment
    # check itself blocks the escape -- not just that the target happens to be missing.
    get "/docs/images/..%2f..%2f..%2fGemfile"

    assert_response :not_found
  end

  test "blocks path traversal out of the claudox images directory" do
    get "/claudox/images/..%2f..%2f..%2fGemfile"

    assert_response :not_found
  end

  test "blocks an absolute path escaping the docs images directory" do
    get "/docs/images/%2Fetc%2Fpasswd"

    assert_response :not_found
  end

  test "img tag survives the chapter sanitize allowlist" do
    html = ActionController::Base.helpers.sanitize(
      '<p>text</p><img src="/docs/images/example.png" alt="설명"><script>alert(1)</script>',
      tags: %w[
        h1 h2 h3 h4 h5 h6 p br hr ul ol li pre code blockquote strong em a img
        table thead tbody tr th td
      ],
      attributes: %w[href target rel src alt]
    )

    assert_includes html, '<img src="/docs/images/example.png" alt="설명">'
    assert_not_includes html, "<script"
  end
end
