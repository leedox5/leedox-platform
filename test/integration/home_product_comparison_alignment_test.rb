require "test_helper"

class HomeProductComparisonAlignmentTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
  end

  test "1. Home #products contains exactly one Chatdox card and one Claudox card" do
    get root_path
    assert_response :success

    assert_select "#products" do
      assert_select "article", count: 2
      assert_select "span", text: "01 / CHATDOX", count: 1
      assert_select "span", text: "02 / CLAUDOX", count: 1
    end
  end

  test "2 & 3. Both product cards display 추천 대상, 목표, 주요 콘텐츠 in identical order with confirmed copy" do
    get root_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)

    # Chatdox card comparison list
    chatdox_article = doc.css("#products article").find { |article| article.text.include?("CHATDOX") }
    assert chatdox_article, "Chatdox card must be present"

    chatdox_dts = chatdox_article.css("dl dt").map(&:text).map(&:strip)
    assert_equal [ "추천 대상", "목표", "주요 콘텐츠" ], chatdox_dts

    chatdox_dds = chatdox_article.css("dl dd").map(&:text).map(&:strip)
    assert_equal "첫 SaaS를 만들고 싶은 비개발자·초급 개발자", chatdox_dds[0]
    assert_equal "AI와 실제 서비스를 기획부터 배포", chatdox_dds[1]
    assert_equal "구축 과정·기술 선택·코드 예제", chatdox_dds[2]

    # Claudox card comparison list
    claudox_article = doc.css("#products article").find { |article| article.text.include?("CLAUDOX") }
    assert claudox_article, "Claudox card must be present"

    claudox_dts = claudox_article.css("dl dt").map(&:text).map(&:strip)
    assert_equal [ "추천 대상", "목표", "주요 콘텐츠" ], claudox_dts

    claudox_dds = claudox_article.css("dl dd").map(&:text).map(&:strip)
    assert_equal "AI 협업 방식을 설계하려는 실무자·기획자·팀 리더", claudox_dds[0]
    assert_equal "반복 가능한 AI 협업 방식 설계", claudox_dds[1]
    assert_equal "질문·기록·역할·업무 프로세스", claudox_dds[2]
  end

  test "4. Product detail CTAs point to respective Chatdox and Claudox landing paths" do
    get root_path
    assert_response :success

    assert_select "#products" do
      assert_select "a[href=?]", chatdox_path, text: /Chatdox 자세히 보기/
      assert_select "a[href=?]", claudox_path, text: /Claudox 자세히 보기/
    end
  end

  test "5. '무엇부터 읽어야 할까요?', 'Choose your starting point', and unconfirmed bundle product note are removed" do
    get root_path
    assert_response :success

    assert_no_match(/Choose your starting point/, response.body)
    assert_no_match(/무엇부터 읽어야 할까요\?/, response.body)
    assert_no_match(/묶음 상품과 구매 조건은 아직 확정되지 않았습니다/, response.body)
    assert_no_match(/두 기록을 함께 탐색/, response.body)
  end

  test "6. FAQ, Aistart free guide banner, and final home CTA are preserved" do
    get root_path
    assert_response :success

    # Aistart free guide banner
    assert_select "a[href=?]", product_content_index_path("aistart"), text: /무료로 읽어보기/

    # FAQ section
    assert_select "#faq"
    assert_select "#faq p", text: "FAQ"
    assert_select "#faq h2", text: "두 상품이 궁금하다면"

    # Final home CTA section
    assert_select "p", text: "Make the next move"
    assert_select "a[href='#products']", text: "나에게 맞는 상품 찾기"
  end

  test "7. Desktop 2-column grid and mobile responsive layout classes are preserved" do
    get root_path
    assert_response :success

    assert_select "#products div.grid.gap-6.lg\\:grid-cols-2"
  end

  test "8. Home page does not display pricing tables or excluded unconfirmed feature promises" do
    get root_path
    assert_response :success

    assert_no_match(/GitHub Private Lab/, response.body)
    assert_no_match(/보장형 지원/, response.body)
    assert_no_match(/얼리버드 20%/, response.body)
  end
end
