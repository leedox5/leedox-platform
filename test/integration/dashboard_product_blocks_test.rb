require "test_helper"

class DashboardProductBlocksTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @user = User.create!(name: "테스트 유저", email: "dashboard-product-blocks@example.com", password: "password123")
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
  end

  test "each product gets its own section grouping status, doc access, progress, recent chapters, and Next Step together" do
    get dashboard_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    %w[Chatdox Claudox].each do |name|
      section = doc.at_css("section[aria-label='#{name} 현황']")
      assert section, "expected a #{name} 현황 section"

      assert_match(/접근 가능 문서/, section.text)
      assert_match(/학습 진도/, section.text)
      assert_match(/최근 완료한 챕터/, section.text)
      assert_match(/Next Step/, section.text)
    end
  end

  test "GitHub Lab entry point is not present in dashboard sections in V1" do
    get dashboard_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    assert_no_match(/GitHub Lab/, response.body)
    assert_nil doc.at_css("section[aria-label='GitHub Lab 연결']"),
      "GitHub Lab should no longer be present in V1 dashboard"
  end

  test "unlicensed products still render their own block (not hidden)" do
    get dashboard_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    assert doc.at_css("section[aria-label='Chatdox 현황']")
    assert doc.at_css("section[aria-label='Claudox 현황']")
  end

  test "a new user sees one first-chapter CTA per product" do
    get dashboard_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    Product.order(:code).each do |product|
      section = doc.at_css("section[aria-label='#{product.name} 현황']")
      first_chapter_id = ProductContent.for(product.code).chapters.first[:id]
      assert_equal 1, section.css("a").count { |link| link.text.strip == "첫 챕터 시작" }
      assert_equal 0, section.css("a").count { |link| link.text.strip == "이어서 학습" }
      assert section.at_css("a[href='#{product_chapter_path(product.code, first_chapter_id)}']"),
        "expected #{product.name} first-chapter CTA"
    end
  end

  test "a user who only completed Chatdox chapters sees accurate Chatdox progress and Next Step, while Claudox stays untouched" do
    post chapter_progresses_path, params: { chapter_id: "01", product_code: "chatdox" }
    post chapter_progresses_path, params: { chapter_id: "02", product_code: "chatdox" }

    get dashboard_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    chatdox_section = doc.at_css("section[aria-label='Chatdox 현황']").text
    claudox_section = doc.at_css("section[aria-label='Claudox 현황']").text

    assert_match(/전체 20개 중 2개 완료/, chatdox_section)
    assert_match(/Chapter 03/, chatdox_section)
    assert_match(/이어서 학습/, chatdox_section)
    assert_match(/전체 20개 중 0개 완료/, claudox_section)
    assert_match(/Chapter 01/, claudox_section)
  end

  test "a user who only completed Claudox chapters sees accurate Claudox progress and Next Step, while Chatdox stays untouched" do
    post chapter_progresses_path, params: { chapter_id: "01", product_code: "claudox" }
    post chapter_progresses_path, params: { chapter_id: "02", product_code: "claudox" }
    post chapter_progresses_path, params: { chapter_id: "03", product_code: "claudox" }

    get dashboard_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    chatdox_section = doc.at_css("section[aria-label='Chatdox 현황']").text
    claudox_section = doc.at_css("section[aria-label='Claudox 현황']").text

    assert_match(/전체 20개 중 3개 완료/, claudox_section)
    assert_match(/Chapter 04/, claudox_section)
    assert_match(/전체 20개 중 0개 완료/, chatdox_section)
    assert_match(/Chapter 01/, chatdox_section)
  end

  test "recent chapter and Next Step links point at the right product via the generic content route" do
    # Dashboard-generated links now go through the generic product_chapter_path
    # (docs/internal/content_platform_design.md section B-2) rather than the
    # legacy claudox_chapter_path/doc_path helpers -- those legacy paths still
    # work as external entry points, but the app no longer generates them itself.
    post chapter_progresses_path, params: { chapter_id: "01", product_code: "claudox" }

    get dashboard_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    claudox_section = doc.at_css("section[aria-label='Claudox 현황']")

    assert claudox_section.css("a[href='#{product_chapter_path('claudox', '01')}']").any?,
      "expected a '다시 보기' link back into #{product_chapter_path('claudox', '01')}"
    assert claudox_section.css("a[href='#{product_chapter_path('claudox', '02')}']").any?,
      "expected the Next Step link to point at #{product_chapter_path('claudox', '02')}"
  end
end
