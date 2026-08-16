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
    # The chapter id already shows in its own icon badge (see
    # leedox_content_template_unification_r1) -- the title text itself has
    # no redundant number prefix.
    assert_match(/소개/, response.body)
    assert_match(/다음 단계/, response.body)

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

  test "relative .md links resolve to the matching chapter, or drop to plain text when nothing matches (handoff 0049)" do
    File.write(@product_path.join("01_intro.md"), <<~MARKDOWN)
      # 소개

      합성 상품 테스트 본문입니다.

      다음 장은 [02_next.md](02_next.md)에 있고, [QNA.md](QNA.md)는 없습니다.
      외부 링크는 [그대로](https://example.com) 유지됩니다.
    MARKDOWN

    get "/content/#{@product_code}/01"
    assert_response :success

    assert_select "a[href=?]", product_chapter_path(@product_code, "02"), text: "02_next.md"
    assert_select "a", text: "QNA.md", count: 0
    assert_match(/QNA\.md는 없습니다/, response.body)
    assert_select "a[href='https://example.com'][target='_blank']", text: "그대로"
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

  test "guest access is actually blocked past guest_chapter_limit, not just allowed at/under it" do
    File.write(@product_path.join("03_third.md"), "# 세 번째\n\n세 번째 챕터 본문.\n")

    get "/content/#{@product_code}/03"
    assert_redirected_to new_user_session_path
  end

  test "a signed-in user sees no 학습 상태 completion panel on an appendix chapter, via the generic template" do
    File.write(@product_path.join("content_meta.yml"), <<~YAML)
      chapter_range: "1..2"
      appendix_range: "90..99"
    YAML
    File.write(@product_path.join("90_appendix.md"), "# 부록\n\n부록 챕터 본문.\n")

    Commerce::CatalogBootstrap.call!
    product = Product.find_or_create_by!(code: @product_code) { |record| record.name = "Synthetic" }
    user = User.create!(name: "테스트 유저", email: "synthetic-appendix-#{SecureRandom.hex(3)}@example.com", password: "password123")
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    end_date = today + 1.month
    License.create!(
      user: user, product: product, source: "paid", status: "active",
      starts_on: today, last_usable_on: end_date - 1.day,
      access_ends_at: Commerce::PeriodCalculator::KST.local(end_date.year, end_date.month, end_date.day)
    )
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    get "/content/#{@product_code}/90"
    assert_response :success
    assert_match(/부록 챕터 본문/, response.body)
    assert_no_match(/학습 상태/, response.body)
    assert_no_match(/이 챕터 완료/, response.body)

    # A regular (non-appendix) chapter for the same signed-in user still gets the panel --
    # the fix must not hide it everywhere, only for kind: :appendix.
    get "/content/#{@product_code}/01"
    assert_response :success
    assert_match(/학습 상태/, response.body)
  end
end
