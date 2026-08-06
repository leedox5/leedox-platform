require "test_helper"

class DashboardProductBlocksTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @user = User.create!(name: "테스트 유저", email: "dashboard-product-blocks@example.com", password: "password123")
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
  end

  test "owned products get detailed main learning section while unowned products appear in bottom catalog grid" do
    grant_license(@user, "chatdox")

    get dashboard_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)

    # Chatdox (owned) appears in main section with full learning block
    chatdox_section = doc.at_css("section[aria-label='Chatdox 현황']")
    assert chatdox_section, "expected a Chatdox 현황 main section"
    assert_match(/접근 가능 문서/, chatdox_section.text)
    assert_match(/학습 진도/, chatdox_section.text)
    assert_match(/최근 완료한 챕터/, chatdox_section.text)
    assert_match(/Next Step/, chatdox_section.text)
    assert chatdox_section.at_css("a[href*='/content/chatdox/']"), "expected learning CTA for owned Chatdox"

    # Claudox (unowned) appears in bottom catalog grid with compact card
    catalog_section = doc.at_css("section[aria-label='전체 카탈로그 둘러보기']")
    assert catalog_section, "expected a 전체 카탈로그 둘러보기 section"
    assert_includes catalog_section.text, "Claudox"
    assert catalog_section.at_css("a[href='#{pricing_path}']"), "expected pricing CTA for unowned Claudox"
  end

  test "GitHub Lab entry point is not present in dashboard sections in V1" do
    get dashboard_path
    assert_response :success

    assert_no_match(/GitHub Lab/, response.body)
    assert_nil Nokogiri::HTML(response.body).at_css("section[aria-label='GitHub Lab 연결']"),
      "GitHub Lab should no longer be present in V1 dashboard"
  end

  test "an unowned user sees onboarding card in main area and all unowned products in bottom catalog" do
    get dashboard_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)

    # Onboarding notice in main section when 0 products are owned
    assert doc.at_css("section[aria-label='학습 중인 상품 없음']")

    # Bottom catalog grid contains compact cards for Chatdox & Claudox
    catalog_section = doc.at_css("section[aria-label='전체 카탈로그 둘러보기']")
    assert catalog_section, "expected catalog grid section"
    assert_includes catalog_section.text, "Chatdox"
    assert_includes catalog_section.text, "Claudox"
  end

  test "a user who completed Chatdox chapters sees accurate Chatdox progress and Next Step" do
    grant_license(@user, "chatdox")
    post chapter_progresses_path, params: { chapter_id: "01", product_code: "chatdox" }
    post chapter_progresses_path, params: { chapter_id: "02", product_code: "chatdox" }

    get dashboard_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    chatdox_section = doc.at_css("section[aria-label='Chatdox 현황']").text

    assert_match(/전체 20개 중 2개 완료/, chatdox_section)
    assert_match(/Chapter 03/, chatdox_section)
    assert_match(/이어서 학습/, chatdox_section)
  end

  test "recent chapter and Next Step links point at the right product via generic content route" do
    grant_license(@user, "claudox")
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

  private

  def grant_license(user, product_code)
    kst = ActiveSupport::TimeZone["Asia/Seoul"]
    today = Date.current
    last_usable = today + 30.days
    access_ends = kst.local((last_usable + 1.day).year, (last_usable + 1.day).month, (last_usable + 1.day).day)
    License.create!(
      user: user, product: Product.find_by!(code: product_code),
      source: "paid", status: "active",
      starts_on: today, last_usable_on: last_usable, access_ends_at: access_ends
    )
  end
end
