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

  # Handoff 0075 -- a one-line revision note right under the effective date; on /terms, 제4조의2 links to the article.
  test "the terms show the revision note under the effective date, linking 제4조의2 to the article" do
    get terms_path
    date, note = css_select("h1 ~ p").first(2).map { |n| n.text.squish }
    assert_equal "시행일: 2026년 10월 4일", date
    assert_equal "개정 안내: 2026년 10월 4일 — 편 댓글 기능 도입에 따라 제4조의2(이용자 게시물)를 추가했습니다.", note
    assert_select "h1 ~ p a[href='#article-4-2']", text: "제4조의2"
    assert_select "#article-4-2 h3", text: "제4조의2 이용자 게시물"
  end

  test "the privacy policy shows its revision note under the effective date" do
    get privacy_path
    date, note = css_select("h1 ~ p").first(2).map { |n| n.text.squish }
    assert_equal "시행일: 2026년 10월 4일", date
    assert_equal "개정 안내: 2026년 10월 4일 — 편 댓글 기능 도입에 따라 수집 항목에 게시물 정보를, 이용 목적에 작성자 표시(이름 일부를 가린 형태)를 추가했습니다.", note
  end

  test "signed-in users and admins see the same notes as guests" do
    [ User.create!(name: "회원", email: "legal-#{SecureRandom.hex(3)}@example.com", password: "password123"),
      User.create!(name: "관리자", email: "legal-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin) ].each do |user|
      post user_session_path, params: { user: { email: user.email, password: "password123" } }
      get terms_path
      assert_includes css_select("body").text.squish, "개정 안내: 2026년 10월 4일 — 편 댓글 기능 도입에 따라 제4조의2(이용자 게시물)를 추가했습니다."
      get privacy_path
      assert_includes css_select("body").text.squish, "개정 안내: 2026년 10월 4일 — 편 댓글 기능 도입에 따라 수집 항목에 게시물 정보를"
      delete destroy_user_session_path
    end
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
