require "test_helper"

# Proves the core claim of the multi-product platform generalization project:
# a product nobody registered anywhere in code still works end-to-end, purely
# because its content exists under hq/<product_code>/ (see ProductContent.for
# and docs/internal/content_platform_design.md section A). Uses a random
# product code + a real temp content folder rather than mocking anything, so
# this exercises the actual routes/controller, not just the model layer.
class SyntheticProductContentTest < ActionDispatch::IntegrationTest
  setup do
    @product_code = "synthetic_test_product_#{SecureRandom.hex(4)}"
    @product_path = Rails.root.join("hq/#{@product_code}")
    FileUtils.mkdir_p(@product_path)
    File.write(@product_path.join("01_intro.md"), "# 소개\n\n합성 상품 테스트 본문입니다.\n")
    File.write(@product_path.join("02_next.md"), "# 다음 단계\n\n두 번째 챕터 본문.\n")
  end

  teardown do
    FileUtils.rm_rf(@product_path)
  end

  test "a product with zero code registration and no content_meta.yml works end-to-end via the generic /content/:product_code route" do
    get "/content/#{@product_code}"
    assert_response :success
    assert_match(/01\.\s*소개/, response.body)
    assert_match(/02\.\s*다음 단계/, response.body)

    get "/content/#{@product_code}/01"
    assert_response :success
    assert_match(/소개/, response.body)
    assert_match(/합성 상품 테스트 본문입니다/, response.body)
  end

  test "guest access follows the default guest_chapter_limit (2) with no content_meta.yml to override it" do
    get "/content/#{@product_code}/01"
    assert_response :success

    get "/content/#{@product_code}/02"
    assert_response :success
  end

  test "a chapter id with no file at all 404s with the FilesystemSource message" do
    get "/content/#{@product_code}/03"
    assert_response :not_found
    assert_match(/아직 공개되지 않은 챕터입니다/, response.body)
  end

  test "image serving works via the generic route too" do
    images_dir = @product_path.join("images")
    FileUtils.mkdir_p(images_dir)
    FileUtils.cp(Rails.root.join("test/fixtures/files/chapter_image_test.png"), images_dir.join("sample.png"))

    get "/content/#{@product_code}/images/sample.png"
    assert_response :success
    assert_equal "image/png", response.media_type
  end
end
