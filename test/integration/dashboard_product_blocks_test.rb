require "test_helper"

# Handoff 0089 -- an owned earlier product is a small card (name, 이용 중, period) linking to its contents; the
# learning block (chapters you can see, progress, recent and next chapters) is gone. Tests that checked that block
# now check the card and that reading records don't bring the block back.
class DashboardProductBlocksTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @user = User.create!(name: "테스트 유저", email: "dashboard-product-blocks@example.com", password: "password123")
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
  end

  test "an owned product gets a small card linking to its contents; unowned products don't show" do
    grant_license(@user, "chatdox")

    get dashboard_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)

    chatdox_section = doc.at_css("section[aria-label='Chatdox 현황']")
    assert chatdox_section, "expected a Chatdox card"
    assert_equal [ product_content_index_path("chatdox") ], chatdox_section.css("a").map { |a| a["href"] }
    assert_no_match(/볼 수 있는 챕터|진행률|최근에 읽은 챕터|다음 챕터/, chatdox_section.text)

    # Claudox (unowned) no longer shows -- 0085: 더 둘러보기 lists series, not earlier products
    assert_no_match(/Claudox/, doc.at_css("main").text)
    assert_nil doc.at_css("main a[href='/pricing']")
  end

  test "GitHub Lab entry point is not present in dashboard sections in V1" do
    get dashboard_path
    assert_response :success

    assert_no_match(/GitHub Lab/, response.body)
    assert_nil Nokogiri::HTML(response.body).at_css("section[aria-label='GitHub Lab 연결']"),
      "GitHub Lab should no longer be present in V1 dashboard"
  end

  test "an unowned user sees onboarding card in main area and no earlier product (0085)" do
    get dashboard_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)

    # Onboarding notice in main section when 0 products are owned
    assert doc.at_css("section[aria-label='이용 중인 콘텐츠 없음']")

    # 0085: earlier products show only while in use; 더 둘러보기 lists series (none in this test)
    assert_no_match(/Chatdox|Claudox/, doc.at_css("main").text)
  end

  test "reading records don't add progress or chapter links back to the card" do
    grant_license(@user, "chatdox")
    post chapter_progresses_path, params: { chapter_id: "01", product_code: "chatdox" }
    post chapter_progresses_path, params: { chapter_id: "02", product_code: "chatdox" }
    assert_equal 2, @user.chapter_progresses.where(product_code: "chatdox").count, "the records themselves are kept"

    get dashboard_path
    assert_response :success

    chatdox_section = css_select("section[aria-label='Chatdox 현황']").first
    assert_no_match(/개 중|Chapter 0|이어서 보기|다시 보기/, chatdox_section.text)
    assert_equal [ product_content_index_path("chatdox") ], chatdox_section.css("a").map { |a| a["href"] }
  end

  test "each card links to its own product's contents" do
    grant_license(@user, "claudox")
    grant_license(@user, "chatdox")

    get dashboard_path
    assert_select "section[aria-label='Claudox 현황'] a[href=?]", product_content_index_path("claudox")
    assert_select "section[aria-label='Chatdox 현황'] a[href=?]", product_content_index_path("chatdox")
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
