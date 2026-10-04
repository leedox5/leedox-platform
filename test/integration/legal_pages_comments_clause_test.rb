require "test_helper"

# Handoff 0074 R3 (o) -- the confirmed posting clause (HQ terms_draft.md) on /terms and /privacy.
class LegalPagesCommentsClauseTest < ActionDispatch::IntegrationTest
  test "the terms carry 제4조의2 이용자 게시물 right after 제4조, with the new effective date" do
    get terms_path
    assert_response :success
    text = css_select("body").text.squish
    assert_includes text, "시행일: 2026년 10월 4일"
    assert_operator text.index("제4조 금지 행위"), :<, text.index("제4조의2 이용자 게시물")
    assert_operator text.index("제4조의2 이용자 게시물"), :<, text.index("제5조")
    [ "게시물의 내용에 대한 책임과 권리는 작성한 이용자에게 있습니다.",
      "작성자 이름의 일부를 가린 표시 이름이 함께 표시됩니다.",
      "제7조의 콘텐츠 권리를 침해하는 내용",
      "사전 통지 없이 해당 게시물을 숨길 수 있습니다. 작성자는 제15조(문의)의 방법으로 이의를 제기할 수 있습니다.",
      "탈퇴 전에 직접 삭제하거나 회사에 요청할 수 있습니다." ].each { |clause| assert_includes text, clause }
    assert_select "ol.list-decimal > li", 5
  end

  test "the privacy policy lists comments as collected data and the masked author display as a purpose" do
    get privacy_path
    assert_response :success
    text = css_select("body").text.squish
    assert_includes text, "시행일: 2026년 10월 4일"
    assert_includes text, "게시물 정보: 이용자가 작성한 댓글 내용과 작성 시각"
    assert_includes text, "댓글 등 게시물의 작성자 표시(이름의 일부를 가린 형태로 다른 이용자에게 표시)"
  end
end
