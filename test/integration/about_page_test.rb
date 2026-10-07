require "test_helper"

# Handoff 0098 -- /about: what LEEDOX is. The brand sentence (h1), the line under it and the 가이드 · 에피소드 · 실전
# blocks moved here from the home with their copy unchanged, then 가이드 보러 가기. Public, dark, indexable; reached
# from the header (LEEDOX 소개, right after 가이드), the footer (first link) and the home's last line.
class AboutPageTest < ActionDispatch::IntegrationTest
  BRAND = "실제로 만들고 부딪히며 엮은 개발자의 실전 가이드."
  LINE = "매끈한 강의 대신, 막히고 고친 과정까지 한 편씩 따라갑니다. Git·Java·WSL 같은 개발 기초부터 AI와 함께 만드는 이야기까지."

  def sign_in(user) = post(user_session_path, params: { user: { email: user.email, password: "password123" } })
  def menu_labels(label) = css_select("nav[aria-label='#{label}'] a").map { |a| a.text.strip }

  test "a guest sees the brand sentence as the one h1, the line, the three blocks and 가이드 보러 가기" do
    get about_path
    assert_response :success
    assert_select "title", text: "LEEDOX 소개 | LEEDOX"
    assert_select "meta[name='description'][content=?]", "#{BRAND} #{LINE}"
    assert_select "meta[name='robots']", 0, "open to search"

    assert_select "h1", count: 1
    h1 = css_select("main h1").first
    assert_equal BRAND, h1.text.strip
    %w[font-display font-bold break-keep text-[28px] leading-9 md:text-[40px]].each { |k| assert_includes h1["class"].split, k }
    assert_equal LINE, h1.next_element.text.strip

    assert_select "section[aria-labelledby='series-explainer'] h2.sr-only", text: "가이드 · 에피소드 · 실전"
    grid = css_select("section[aria-labelledby='series-explainer'] .grid").first
    assert_includes grid["class"].split, "md:grid-cols-3"
    assert_equal [
      [ "가이드", "하나의 주제, 하나의 완결", "Git, Java, WSL, AI 협업처럼 주제마다 가이드 하나. 그 자체로 끝까지 갑니다." ],
      [ "에피소드", "한 편에 한 장면", "각 편은 질문 하나에 답하고, 다음 편의 질문을 남기며 끝납니다." ],
      [ "실전", "부딪힌 자리까지", "잘 된 결과만이 아니라, 막히고 고친 과정을 그대로 엮었습니다." ]
    ], grid.css("> div").map { |d| d.css("p, h3").map { |n| n.text.strip } }

    button = css_select("main a").find { |a| a.text.strip == "가이드 보러 가기" }
    assert_equal products_path, button["href"]
    assert_includes button["class"].split, "bg-accent"

    html = css_select("main").first.to_html
    assert_operator html.index(BRAND), :<, html.index("series-explainer")
    assert_operator html.index("series-explainer"), :<, html.index("가이드 보러 가기")
  end

  test "dark like the home, 10px phone margins, and the display font" do
    get about_path
    assert_select "div.bg-page > header.bg-page\\/90"
    assert_select "link[rel='preload'][href*='Pretendard-Bold']", 1
    %w[px-2.5 sm:px-7].each { |k| assert_includes css_select("main > section").first["class"].split, k }
    assert_includes css_select("section[aria-labelledby='series-explainer'] > div").first["class"].split, "px-2.5"
  end

  test "LEEDOX 소개 sits right after 가이드 in the header (desktop and mobile) and first in the footer, for guests and members" do
    get root_path
    assert_equal [ "가이드", "LEEDOX 소개" ], menu_labels("주요 내비게이션").first(2)
    assert_equal [ "가이드", "LEEDOX 소개" ], menu_labels("모바일 내비게이션").first(2)
    assert_select "nav[aria-label='주요 내비게이션'] a[href=?]", about_path, text: "LEEDOX 소개"
    assert_equal [ "LEEDOX 소개", about_path ], css_select("footer a").map { |a| [ a.text.strip, a["href"] ] }.first

    member = User.create!(name: "회원", email: "about-#{SecureRandom.hex(3)}@example.com", password: "password123")
    sign_in(member)
    get about_path
    assert_response :success
    assert_equal [ "가이드", "LEEDOX 소개", "대시보드" ], menu_labels("주요 내비게이션").first(3)
    assert_select "main h1", text: BRAND
  end
end
