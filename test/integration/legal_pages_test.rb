require "test_helper"

class LegalPagesTest < ActionDispatch::IntegrationTest
  test "terms page is restructured into common sections plus a per-product scope table" do
    get terms_path
    assert_response :success

    assert_match(/총칙/, response.body)
    assert_match(/계정 및 이용자 의무/, response.body)
    assert_match(/라이선스 일반 원칙/, response.body)
    assert_match(/상품별 제공 범위/, response.body)
    assert_match(/결제·환불/, response.body)
    assert_match(/면책·분쟁해결/, response.body)

    doc = Nokogiri::HTML(response.body)
    table = doc.at_css("table")
    assert table, "expected a per-product scope table"
    rows = table.css("tbody tr").map { |row| row.css("td").map(&:text) }
    assert_equal 2, rows.size
    assert_equal "Chatdox", rows[0][0]
    assert_match(/미포함/, rows[0][2])
    assert_equal "미포함", rows[0][3]
    assert_equal "Claudox", rows[1][0]
    assert_equal "미포함", rows[1][2]
    assert_equal "미포함", rows[1][3]
  end

  test "terms page reflects QA/03 V1 product definitions for Chatdox and Claudox" do
    get terms_path
    assert_response :success
    body = response.body

    # Common license principles carried over from the old 제4조/제4조의2.
    assert_match(/기간제 선불 라이선스 방식으로 제공되며, 별도 동의 없는 자동 갱신이나 정기 결제는 이루어지지 않습니다/, body)
    assert_match(/1개월, 3개월, 6개월, 12개월 중 선택할 수 있/, body)
    assert_match(/결제일을 포함한 7일 이내에서 이용자가 선택할 수 있으며/, body)
    assert_match(/한국 표준시\(KST\) 기준으로 계산되며, 마지막 이용일 다음 날 00:00부터 접근이 종료/, body)
    assert_match(/이용 시작 전 결제를 취소하는 경우 원칙적으로 전액 환불/, body)
    assert_match(/청약철회가 인정되는 경우에 한하여/, body)

    # New common policy statements required by this round.
    assert_match(/부가가치세\(VAT\)가 포함된 금액/, body)
    assert_match(/소급하여 영향을 받지 않습니다/, body)
    assert_match(/이용 기간이 합산되지 않습니다/, body)
    assert_match(/제3자에게 양도하거나 공유할 수 없습니다/, body)

    # Chatdox-specific V1 clauses -- aligned with QA/03.
    assert_match(/핵심 웹 챕터 20개, 챕터 설명 및 코드 예제/, body)
    assert_match(/예제 코드를 학습하고 자신의 개인 프로젝트에 수정 및 적용하여 배포·운영할 수 있습니다/, body)
    assert_match(/LEEDOX가 제공한 원문 콘텐츠, 이미지, 문서를 복제·재배포·재판매하거나/, body)
    assert_match(/템플릿이나 강의 형태로 재구성하여 판매하는 행위는 금지됩니다/, body)

    # Common misconduct/liability/change/contact clauses carried over unchanged.
    assert_match(/타인의 계정 또는 결제 정보를 무단으로 사용하는 행위/, body)
    assert_match(/천재지변, 통신 장애, 결제대행사 또는 외부 플랫폼 장애/, body)
    assert_match(/leedox@naver\.com/, body)
  end

  test "terms page reflects Claudox V1 scope without source code or repository access" do
    get terms_path
    assert_response :success
    body = response.body

    assert_match(/Claudox 이용 기간 중에는 핵심 웹 챕터 20개, 라이선스 전용 특별판/, body)
    assert_match(/소스코드 전체, 다운로드용 템플릿 파일 묶음.*GitHub 저장소 접근.*포함되지 않습니다/, body)
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
