require "test_helper"

class AigravityLandingPageTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
  end

  test "renders /aigravity landing page with Emerald theme, starter badge, and 14 chapter links" do
    get aigravity_path
    assert_response :success

    # Emerald theme & title
    assert_select "title", text: /Antigravity \| 따라하며 배우는 무중력 AI 코딩 마스터클래스/
    assert_select "h1", text: /무중력 AI 코딩 마스터클래스/
    assert_select "p", text: /AI-NATIVE STARTER PACKAGE/

    # Hero CTA link to episode 01
    assert_select "a[href=?]", product_chapter_path("aigravity", "01"), text: /무중력 코딩 시작하기/

    # 14 chapters across 4 phases
    doc = Nokogiri::HTML(response.body)
    (1..14).each do |id|
      padded_id = format("%02d", id)
      link = doc.at_css("a[href='#{product_chapter_path('aigravity', padded_id)}']")
      assert link, "expected curriculum link for chapter #{padded_id}"
    end

    # Bottom Dark Banner & FAQ
    assert_select "h2", text: /지금 바로 무중력 AI 코딩 마스터클래스를 시작하세요/
    assert_select "h2", text: /자주 묻는 질문 \(FAQ\)/
  end
end
