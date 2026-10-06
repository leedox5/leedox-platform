require "test_helper"

# Handoff 0088 -- the terms name no product: common sections plus a per-product-type scope table (시리즈 / 기간제 콘텐츠
# 상품), the two license methods in 제5조, 제9조 for every product, 제10조 판매 종료 상품 and 부칙. The first three tests
# used to check the Chatdox / Claudox table and 제9조·제10조 (QA/03 V1); they now check the same places in their new form.
class LegalPagesTest < ActionDispatch::IntegrationTest
  test "terms page is restructured into common sections plus a per-product-type scope table" do
    get terms_path
    assert_response :success

    assert_match(/총칙/, response.body)
    assert_match(/계정 및 이용자 의무/, response.body)
    assert_match(/라이선스 일반 원칙/, response.body)
    assert_match(/IV\. 상품 유형별 제공 범위/, response.body)
    assert_match(/결제·환불/, response.body)
    assert_match(/면책·분쟁해결/, response.body)

    doc = Nokogiri::HTML(response.body)
    table = doc.at_css("table")
    assert table, "expected a per-product-type scope table"
    assert_equal [ "상품 유형", "이용 방식", "제공 콘텐츠", "포함되지 않는 것" ], table.css("thead th").map { |th| th.text.strip }
    rows = table.css("tbody tr").map { |row| row.css("td").map { |td| td.text.strip } }
    # 0091 (D-011): the type is called 가이드 (was 시리즈).
    assert_equal [ "가이드", "무기한 이용(한 번 결제 또는 무료 이용 시작)",
      "해당 가이드에 공개된 편과 편에 딸린 자료·첨부 파일, 이후 같은 가이드에 추가되는 편", "다른 가이드, 별도 상품으로 출시되는 콘텐츠" ], rows[0]
    assert_equal [ "기간제 콘텐츠 상품", "기간제 이용", "상품 페이지에 표시된 웹 챕터와 이용 기간 중 추가되는 웹 콘텐츠", "다른 상품" ], rows[1]
    assert_equal 2, rows.size
    assert_no_match(/Chatdox|Claudox/, doc.at_css("main, body").text)
  end

  test "terms page states both license methods and the common principles" do
    get terms_path
    assert_response :success
    body = response.body

    # 제5조 -- 무기한 이용 / 기간제 이용, both prepaid, no auto-renewal; the period rules now apply to 기간제 이용.
    assert_match(/무기한 이용<\/strong>: 한 번 결제하거나 무료로 이용을 시작하면 기간 제한 없이 이용합니다/, body)
    assert_match(/기간제 이용<\/strong>: 이용자가 선택한 기간 동안 이용합니다/, body)
    assert_match(/어느 방식이든 선불이며, 별도 동의 없는 자동 갱신이나 정기 결제는 이루어지지 않습니다/, body)
    assert_match(/회사가 해당 상품을 서비스하는 동안 기간 제한 없이 이용할 수 있음을 뜻합니다/, body)
    assert_match(/기간제 이용의 이용 기간은 1개월, 3개월, 6개월, 12개월 중 선택할 수 있/, body)
    assert_match(/결제일을 포함한 7일 이내에서 이용자가 선택할 수 있으며/, body)
    assert_match(/한국 표준시\(KST\) 기준으로 계산되며, 마지막 이용일 다음 날 00:00부터 접근이 종료/, body)
    assert_match(/이용 시작 전 결제를 취소하는 경우 원칙적으로 전액 환불/, body)
    assert_match(/청약철회가 인정되는 경우에 한하여/, body)

    # 제6조·제7조
    assert_match(/부가가치세\(VAT\)가 포함된 금액/, body)
    assert_match(/이미 결제를 완료했거나 무료로 이용을 시작한 라이선스는 이후 가격이 변경되더라도 소급하여 영향을 받지 않습니다/, body)
    assert_match(/무기한 이용 상품에는 연장 결제가 없습니다/, body)
    assert_match(/이용 기간도 합산되지 않습니다/, body)
    assert_match(/제3자에게 양도하거나 공유할 수 없습니다/, body)
    assert_match(/허용되는 이용 범위의 예외는 제9조에서 정합니다/, body)

    # Common misconduct/liability/change/contact clauses carried over unchanged.
    assert_match(/타인의 계정 또는 결제 정보를 무단으로 사용하는 행위/, body)
    assert_match(/천재지변, 통신 장애, 결제대행사 또는 외부 플랫폼 장애/, body)
    assert_match(/leedox@naver\.com/, body)
  end

  test "제9조 applies to every product, 제10조 covers products taken off sale, and 부칙 closes the terms" do
    get terms_path
    doc = Nokogiri::HTML(response.body)
    headings = doc.css("h3").map { |h| h.text.strip }
    numbers = headings.map { |h| h[/\A제\d+조(?:의\d+)?/] }
    assert_equal %w[제1조 제2조 제3조 제4조 제4조의2 제5조 제6조 제7조 제8조 제9조 제10조 제11조 제12조 제13조 제14조 제15조], numbers,
      "every article, in order, no renumbering"
    assert_includes headings, "제8조 상품 유형별 제공 범위"
    assert_includes headings, "제9조 이용 범위 및 금지 행위"
    assert_includes headings, "제10조 판매 종료 상품"

    article9 = doc.css("h3").find { |h| h.text.strip == "제9조 이용 범위 및 금지 행위" }.parent
    assert_equal 3, article9.css("ol > li").size
    assert_match(/강의·템플릿·교재 형태의 상품으로 재구성하여 판매할 수 없습니다/, article9.text)
    assert_match(/LEEDOX 운영 플랫폼의 소스코드 전체, 별도 다운로드용 소스코드·템플릿 파일 묶음, 비공개 저장소 접근, 응답 시간을 보장하는 지원/, article9.text)
    assert_match(/이미 발급된 라이선스는 남은 이용 기간 동안\(무기한 이용 상품은 제5조 제3항에 따라\) 그대로 유지됩니다/, response.body)

    addenda = doc.at_css("section#addenda")
    assert_equal "부칙", addenda.at_css("h2").text.strip
    items = addenda.css("ol > li").map { |li| li.text.strip }
    assert_equal "이 개정 약관은 2026년 10월 6일부터 시행합니다.", items[0]
    assert_match(/시행일 전에 기간제 콘텐츠 상품의 라이선스를 구매한 이용자에게는/, items[1])
    # 0091: the old name maps onto the new one.
    assert_equal "종전 약관의 \"시리즈\"는 이 약관의 \"가이드\"와 같은 상품 유형을 가리키며, 이미 발급된 라이선스의 이용 조건은 달라지지 않습니다.", items[2]
    assert_equal 3, items.size
    assert_equal addenda, doc.css("section").last, "부칙 is the last section, after 제15조"
  end

  test "privacy page no longer names Chatdox specifically" do
    get privacy_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    assert_no_match(/Chatdox/, doc.at_css("title").text)
    assert_no_match(/Chatdox/, doc.at_css("div.space-y-8").text)
    assert_match(/현재 V1 서비스에서는 GitHub 계정 및 저장소 연동 정보를 수집하지 않습니다/, response.body)
  end
end
