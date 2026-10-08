require "test_helper"
require "open3"
require "tmpdir"
require "tailwindcss/ruby"

# Handoff 0105 -- the episode page: the guide's name as a small heading above the title (no "← name" link), 최종
# 업데이트 at the end with the date only, no empty prev / next row, tighter phone values; the body's phone density on
# .doc-content-dark only; the sticky 길잡이 줄 for episodes with three or more body h2s.
class EpisodePageDensityTest < ActionDispatch::IntegrationTest
  BODY_LONG = "도입 문단\n\n## 첫째\n\n문단\n\n## 둘째\n\n> 인용\n\n## 셋째\n\n```\ncode\n```\n\n## 넷째\n\n끝"
  BODY_SHORT = "도입\n\n## 하나\n\n문단\n\n## 둘\n\n끝"

  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "ep-adm-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @member = User.create!(name: "회원", email: "ep-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    @line = ProductLine.create!(internal_name: "ep", customer_name: "밀도 가이드", slug: "ep-guide", summary: "요약", introduction: "소개", status: "published")
    @long = @line.content_episodes.create!(position: 1, customer_title: "아주 긴 제목의 첫 편", body: BODY_LONG, status: "published", open_preview: true)
    @short = @line.content_episodes.create!(position: 2, customer_title: "둘째 편", body: BODY_SHORT, status: "published")
    @long.content_takeaways.create!(kind: "체크리스트", body: "## 요점 제목\n\n- 항목", position: 1)
    Commerce::ProductLineSales.set_price!(product_line: @line, total_amount: 0, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: @line.reload, actor: @admin)
  end

  def sign_in(user) = post(user_session_path, params: { user: { email: user.email, password: "password123" } })
  def classes(node) = node["class"].split
  def main = css_select("main").first

  # --- (가) ------------------------------------------------------------------------------------------------------

  test "the guide's name is a small link above the title; no ← link; the title wraps between words; phone values" do
    get product_episode_path("ep-guide", "01")
    assert_response :success
    assert_no_match(/←/, main.to_html.split("doc-content doc-content-dark").first)
    block = main.element_children.first
    guide, title = block.element_children
    assert_equal product_line_path("ep-guide"), guide["href"]
    assert_equal "밀도 가이드", guide.text.strip
    %w[text-xs font-bold text-accent-ink].each { |k| assert_includes classes(guide), k }
    assert_equal "h1", title.name
    %w[mt-1 break-keep break-words font-display text-[22px] leading-[30px] sm:text-3xl sm:leading-9].each { |k| assert_includes classes(title), k } # HQ R1: 36px from sm
    %w[mb-3.5 pb-2.5 border-b sm:mb-5 sm:pb-3].each { |k| assert_includes classes(block), k } # 0106: sm 20px / 12px
    assert_not_includes block.text, "최종 업데이트"
    %w[px-2.5 pt-3 pb-10 sm:px-7 sm:pt-6 max-w-3xl].each { |k| assert_includes classes(main), k } # 0106: sm 24px above, 40px below as before
    assert_not_includes classes(main), "sm:py-10"
  end

  # --- (라) ------------------------------------------------------------------------------------------------------

  test "최종 업데이트 sits after the body (and its 실전 자료), date only; an empty prev / next row isn't drawn" do
    get product_episode_path("ep-guide", "01") # guest on the 열린 편: no prev, and the next one wouldn't open
    updated = css_select("main [data-episode-updated]").first
    assert_match(/\A최종 업데이트: \d{4}년 \d{1,2}월 \d{1,2}일\z/, updated.text.strip)
    %w[mt-6 text-xs text-ink-3].each { |k| assert_includes classes(updated), k }
    html = main.to_html
    assert_operator html.index("doc-content doc-content-dark"), :<, html.index("data-episode-updated")
    assert_operator html.index("이 편의 실전 자료"), :<, html.index("data-episode-updated")
    assert_select "main [data-episode-nav]", 0
    assert_operator html.index("data-episode-updated"), :<, html.index("continue-box")
  end

  test "member in use: the prev / next row is there with the phone spacing; comments closer on phones" do
    sign_in(@member)
    post claim_free_access_path(@line.product.code)
    get product_episode_path("ep-guide", "02")
    row = css_select("main [data-episode-nav]").first
    assert row
    %w[mt-6 pt-5 sm:mt-16 sm:pt-8 border-t].each { |k| assert_includes classes(row), k }
    html = main.to_html
    assert_operator html.index("data-episode-updated"), :<, html.index("data-episode-nav")
    %w[mt-7 pt-6 sm:mt-12 sm:pt-8].each { |k| assert_includes classes(css_select("#comments").first), k }
  end

  # --- (다) ------------------------------------------------------------------------------------------------------

  test "three or more body h2s: the 길잡이 줄 with 처음으로 + every h2, each h2 with its id; takeaway headings not counted" do
    get product_episode_path("ep-guide", "01")
    toc = css_select("[data-episode-toc]").first
    assert toc
    assert toc.key?("hidden"), "hidden until the script shows it"
    %w[sticky top-[65px] z-40 border-b border-line/12 bg-page/96 backdrop-blur].each { |k| assert_includes classes(toc), k }
    assert_equal "header", toc.previous_element.name, "right under the header, outside main"
    button = toc.at_css("button")
    assert_equal "false", button["aria-expanded"]
    assert_equal "목차", button.at_css("[data-episode-toc-target='current']").text.strip
    nav = toc.at_css("nav[aria-label='이 편의 목차']")
    assert nav.key?("hidden")
    items = nav.css("a")
    assert_equal %w[처음으로 첫째 둘째 셋째 넷째], items.map { |a| a.text.strip }
    assert_equal %w[# #section-1 #section-2 #section-3 #section-4], items.map { |a| a["href"] }
    assert_equal %w[section-1 section-2 section-3 section-4], css_select(".doc-content-dark > h2[id]").map { |h| h["id"] }
    assert_not_includes items.map(&:text).join, "요점 제목"
    assert_empty css_select("section h2[id], .rounded-xl h2[id]"), "takeaway headings get no id"
  end

  test "two h2s or fewer: no 길잡이 줄 (the h2s still get ids)" do
    sign_in(@member)
    post claim_free_access_path(@line.product.code)
    get product_episode_path("ep-guide", "02")
    assert_select "[data-episode-toc]", 0
    assert_equal %w[section-1 section-2], css_select(".doc-content-dark > h2[id]").map { |h| h["id"] }
  end

  test "the admin episode preview: light body, no 길잡이 줄, no ids" do
    sign_in(@admin)
    get admin_content_episode_path(@long)
    assert_response :success
    assert_select "[data-episode-toc]", 0
    assert_select "h2[id^='section-']", 0
    assert_select ".doc-content-dark", 0
    assert_select ".doc-content", minimum: 1
  end

  test "the script: shows the bar, scrolls in place (no visit), keeps the counter, the line and the list state" do
    js = File.read(Rails.root.join("app/javascript/controllers/episode_toc_controller.js"))
    assert_includes js, "this.element.hidden = false"
    assert_includes js, "event.preventDefault()"
    assert_includes js, 'scrollIntoView({ block: "start" })'
    assert_includes js, '"목차"'
    assert_includes js, "`${index + 1} / ${this.sections.length}`"
    assert_includes js, "scaleX("
    assert_includes js, '"Escape"'
    assert_includes js, "aria-expanded"
  end

  # --- (나) ------------------------------------------------------------------------------------------------------

  test "the phone density is in the built CSS for .doc-content-dark only; every width keeps words whole and uses the display face" do
    css = Dir.mktmpdir do |dir|
      out = File.join(dir, "t.css")
      _o, err, status = Open3.capture3(Tailwindcss::Ruby.executable, "-i", Rails.root.join("app/assets/tailwind/application.css").to_s,
        "-o", out, "--minify", chdir: Rails.root.to_s)
      assert status.success?, err
      File.read(out)
    end
    phone = css[/@media not all and \(min-width:40rem\)\{\.doc-content-dark p,.*?\.doc-content-dark td\{font-size:13px\}\}/m]
    assert phone, "the phone block"
    {
      ".doc-content-dark p,.doc-content-dark li{" => "font-size:15px;line-height:24px",
      ".doc-content-dark p{" => "margin-bottom:10px",
      ".doc-content-dark pre{" => "margin-top:10px;margin-bottom:10px;padding:9px 12px;font-size:13px;line-height:20px",
      ".doc-content-dark code{" => "font-size:13px",
      ".doc-content-dark blockquote{" => "margin-top:12px;margin-bottom:12px;padding:8px 12px",
      ".doc-content-dark blockquote p{" => "margin-bottom:0",
      ".doc-content-dark h1{" => "margin-top:20px;margin-bottom:8px;font-size:21px;line-height:28px", # HQ R1
      ".doc-content-dark hr{" => "margin-top:22px;margin-bottom:0",
      ".doc-content-dark h2{" => "margin-top:18px;margin-bottom:8px;font-size:19px;line-height:26px",
      ".doc-content-dark h3{" => "margin-top:16px;margin-bottom:6px;font-size:16px;line-height:24px"
    }.each { |selector, decls| assert_includes phone, "#{selector}#{decls}}", selector }
    assert_no_match(/\.doc-content (p|h2|pre)\{[^}]*15px/, phone, "the light .doc-content isn't touched")
    assert_match(/\.doc-content-dark\{word-break:keep-all;overflow-wrap:break-word\}/, css)
    assert_match(/\.doc-content-dark h1,\.doc-content-dark h2,\.doc-content-dark h3\{font-family:var\(--font-display\);letter-spacing:-\.02em\}/, css)
    assert_match(/\.doc-content-dark h2\[id\]\{scroll-margin-top:112px\}/, css)
  end

  # Handoff 0106 -- sm and up: tighter with the 16px text kept; the phone block above is unchanged.
  test "the sm-and-up body values are in the built CSS for .doc-content-dark only, with no font size for text" do
    css = Dir.mktmpdir do |dir|
      out = File.join(dir, "t.css")
      _o, err, status = Open3.capture3(Tailwindcss::Ruby.executable, "-i", Rails.root.join("app/assets/tailwind/application.css").to_s,
        "-o", out, "--minify", chdir: Rails.root.to_s)
      assert status.success?, err
      File.read(out)
    end
    pc = css[/@media \(min-width:40rem\)\{\.doc-content-dark p,\.doc-content-dark li\{line-height:26px\}.*?\.doc-content-dark h3\{[^}]*\}\}/m]
    assert pc, "the sm-and-up block"
    {
      ".doc-content-dark p{" => "margin-bottom:14px",
      ".doc-content-dark ul,.doc-content-dark ol{" => "margin-top:14px;margin-bottom:14px",
      ".doc-content-dark li{" => "margin-bottom:6px",
      ".doc-content-dark pre{" => "margin-top:12px;margin-bottom:12px;padding:12px 16px",
      ".doc-content-dark blockquote{" => "margin-top:14px;margin-bottom:14px;padding:10px 16px",
      ".doc-content-dark blockquote p{" => "margin-bottom:0",
      ".doc-content-dark hr{" => "margin-top:28px;margin-bottom:0",
      ".doc-content-dark h1{" => "margin-top:28px;margin-bottom:10px;font-size:26px;line-height:34px",
      ".doc-content-dark h2{" => "margin-top:24px;margin-bottom:10px;font-size:22px;line-height:30px",
      ".doc-content-dark h3{" => "margin-top:20px;margin-bottom:6px;font-size:18px;line-height:26px"
    }.each { |selector, decls| assert_includes pc, "#{selector}#{decls}}", selector }
    assert_no_match(/\.doc-content-dark (p|li|pre|code|blockquote)[^{]*\{[^}]*font-size/, pc, "text sizes stay as they are (16px, the 14px box)")
    assert_no_match(/\.doc-content (p|h2|pre)\{/, pc, "the light .doc-content isn't touched")
    assert_includes css, ".doc-content-dark p{margin-bottom:10px}", "the phone block (0105) is still there"
  end

  test "pages with only the light body keep it: a notice and the admin preview" do
    announcement = Announcement.create!(title: "공지", body: "## 제목\n\n본문", published: true)
    get announcement_path(announcement)
    assert_select ".doc-content", minimum: 1
    assert_select ".doc-content-dark", 0
  end
end
