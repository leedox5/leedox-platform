require "test_helper"

# Handoff 0094 -- A: the guide page is denser on phones (below sm; sm and up keep the old values) -- no back-to-list
# line, 10px page margins, a tighter header box / access box / section links / episode heading and cards, the card
# status on the title's line and an 열린 편 badge at the start of the teaser line. The admin preview (the light theme)
# is unchanged. B: the display face is Pretendard Bold from our own assets (was Gowun Batang from Google Fonts).
class GuideDensityTest < ActionDispatch::IntegrationTest
  FONT = "link[rel='preload'][href*='Pretendard-Bold'][as='font'][type='font/woff2'][crossorigin]"

  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "gd-adm-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @line = ProductLine.create!(internal_name: "d", customer_name: "촘촘한 가이드", slug: "dense-guide", summary: "한 줄 요약",
      introduction: "## 첫 제목\n\n소개", status: "published")
    @line.content_episodes.create!(position: 1, customer_title: "첫 편", summary: "첫 편 예고", body: "본문", status: "published", open_preview: true)
    @line.content_episodes.create!(position: 2, customer_title: "둘째 편", body: "본문", status: "published")
    @line.content_episodes.create!(position: 3, customer_title: "예정 편", body: "본문", status: "draft")
    Commerce::ProductLineSales.set_price!(product_line: @line, total_amount: 0, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: @line.reload, actor: @admin)
  end

  def classes(selector) = css_select(selector).first["class"].split

  def assert_classes(selector, *expected)
    actual = classes(selector)
    expected.each { |klass| assert_includes actual, klass, "#{selector}: #{actual.join(' ')}" }
  end

  # --- A ---------------------------------------------------------------------------------------------------------

  test "no back-to-list line; 10px side and top margins on phones" do
    get product_line_path("dense-guide")
    assert_select "a", text: /가이드 목록/, count: 0
    assert_classes "main", "px-2.5", "pt-2.5", "sm:px-7", "sm:pt-6"
  end

  test "the header box, name, summary and the access box inside are tighter on phones" do
    get product_line_path("dense-guide")
    assert_classes "[data-guide-header]", "p-3.5", "sm:px-6", "sm:py-7"
    assert_classes "[data-guide-header] h1", "text-2xl", "sm:text-3xl", "md:text-4xl", "font-display"
    assert_classes "[data-guide-header] p", "mt-1.5", "text-[15px]", "leading-[23px]", "sm:mt-2", "sm:text-lg", "sm:leading-7"
    assert_classes "#product-purchase", "mt-3.5", "pt-3.5", "sm:mt-5", "sm:pt-5", "border-t"
    assert_classes "#product-purchase a", "px-4", "py-[7px]", "sm:px-6", "sm:py-3", "text-sm" # 이용하기, 34px tall on phones
  end

  # 0095: a guide with an image gets the header box too (cover on top); the text under the cover has the same padding.
  test "a guide with an image: the text under the cover has the header box's phone padding" do
    @line.cover_image.attach(io: file_fixture("covers/cover.jpg").open, filename: "c.jpg", content_type: "image/jpeg")
    @line.update!(cover_image_alt: "표지")
    get product_line_path("dense-guide")
    assert_classes "[data-guide-cover] > div", "p-3.5", "sm:px-6", "sm:py-7"
    assert_classes "#product-purchase", "mt-3.5", "pt-3.5", "border-t"
  end

  test "section links: 16px at every width, closer on phones; the intro starts 16px below on phones" do
    get product_line_path("dense-guide")
    assert_classes "nav[aria-label='가이드 바로가기']", "-mx-2.5", "px-2.5", "mt-3", "sm:-mx-7", "sm:px-7", "sm:mt-6", "sticky"
    assert_classes "nav[aria-label='가이드 바로가기'] ul", "text-base"
    assert_classes "nav[aria-label='가이드 바로가기'] a", "py-2", "sm:py-2.5"
    assert_classes "#intro > div", "mt-4", "guide-intro", "sm:mt-11" # R2: guide-intro drops the first element's top margin on phones
  end

  test "episode heading and cards: smaller and closer on phones, the status on the title's line" do
    get product_line_path("dense-guide")
    assert_classes "h2#episodes", "text-[21px]", "mt-[22px]", "mb-2.5", "sm:text-2xl", "sm:mt-8", "sm:mb-3"
    assert_classes "#episodes + ol", "space-y-2", "sm:space-y-3"
    card = css_select("#episodes + ol > li > a").first
    assert_includes card["class"].split, "py-[11px]"
    assert_includes card["class"].split, "sm:p-4"
    row = card.at_css("div")
    assert_not_includes row["class"].split, "flex-wrap"
    assert_equal "보기 →", row.element_children.last.text.strip
    assert_includes row.element_children.last["class"].split, "ml-auto"
    assert_not_includes row.element_children.last["class"].split, "w-full"

    upcoming = css_select("#episodes + ol > li > div").first
    assert_not_includes upcoming.at_css("div")["class"].split, "flex-wrap"
    assert_includes upcoming["class"].split, "py-[11px]"
  end

  test "an 열린 편's badge leads the teaser line on phones and sits on the title's line from sm" do
    get product_line_path("dense-guide")
    card = css_select("#episodes + ol > li > a").first
    title_badge = card.at_css("div > span")
    assert_equal "로그인 없이 보기", title_badge.text.strip
    assert_includes title_badge["class"].split, "hidden"
    assert_includes title_badge["class"].split, "sm:inline-block"
    teaser = card.at_css("p")
    assert_equal [ "로그인 없이 보기", "첫 편 예고" ], teaser.css("span").map { |s| s.text.strip }
    assert_includes teaser.css("span").first["class"].split, "sm:hidden"
    assert_includes teaser.css("span").last["class"].split, "truncate"
  end

  test "the admin preview keeps its sizes and card layout" do
    post user_session_path, params: { user: { email: @admin.email, password: "password123" } }
    get admin_product_line_path(@line)
    assert_classes "main h1", "text-3xl", "md:text-4xl"
    assert_not_includes classes("main h1"), "text-2xl"
    card_row = css_select("main ol > li > a > div").first
    assert_includes card_row["class"].split, "flex-wrap"
    assert_includes css_select("main ol > li > a").first["class"].split, "p-4"
  end

  # --- R2 ---------------------------------------------------------------------------------------------------------

  test "R2-1: the intro's first element loses its top margin on phones via an unlayered rule, on the guide page only" do
    css = File.read(Rails.root.join("app/assets/tailwind/application.css"))
    assert_match(/@media \(width < 40rem\) \{\s*\.guide-intro > :first-child \{\s*margin-top: 0;/m, css)
    before = css[0...css.index(".guide-intro >")]
    assert_equal before.scan("{").size - before.scan(/@media[^{]*\{/).size, before.scan("}").size, "not inside an @layer block"
    get product_line_path("dense-guide")
    assert_select "#intro .guide-intro.doc-content > h2:first-child", text: "첫 제목"
    get product_episode_path("dense-guide", "01")
    assert_select ".guide-intro", 0 # an episode body keeps its first heading's margin
    get announcements_path
    assert_select ".guide-intro", 0
  end

  # [first-row status (nil when hidden on phones), second-line texts] per card, as a phone shows them
  def phone_cards
    css_select("#episodes + ol > li > *").map do |card|
      status = card.at_css("div > span:last-child")
      shown = status["class"].split.include?("hidden") ? nil : status.text.strip
      meta = card.at_css("p")
      [ shown, meta ? meta.css("span").map { |x| x.text.strip } : [] ]
    end
  end

  test "R2-2 (③), guest: 보기 → on the 열린 편's first row; other statuses lead the second line, then the teaser" do
    @line.content_episodes.find_by!(position: 2).update!(summary: "둘째 예고")
    @line.content_episodes.find_by!(position: 3).update!(summary: "예정 예고")
    get product_line_path("dense-guide")
    assert_equal [
      [ "보기 →", [ "로그인 없이 보기", "첫 편 예고" ] ],
      [ nil, [ "로그인 후 보기", "·", "둘째 예고" ] ],
      [ nil, [ "공개 예정", "·", "예정 예고" ] ]
    ], phone_cards
    title = css_select("#episodes + ol > li > a > div > span.flex-1").first
    %w[break-keep break-words sm:truncate].each { |klass| assert_includes title["class"].split, klass }
    assert_not_includes title["class"].split, "truncate"
    assert_includes css_select("#episodes + ol > li > a > p").first["class"].split, "text-[13px]"
  end

  test "R2-2, member before use: 이용 시작 후 보기 leads the second line; in use: every card 보기 → on its row" do
    member = User.create!(name: "회원", email: "gd-m-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    post user_session_path, params: { user: { email: member.email, password: "password123" } }
    get product_line_path("dense-guide")
    assert_equal [ nil, [ "이용 시작 후 보기" ] ], phone_cards[1]
    post claim_free_access_path(@line.product.code)
    get product_line_path("dense-guide")
    assert_equal [ "보기 →", [ "첫 편 예고" ] ], phone_cards[0]
    assert_equal [ "보기 →", [] ], phone_cards[1]
  end

  test "R2-2, member who hasn't bought a paid guide: 구매 후 보기 on the second line, 미리 보기 badge on the 열린 편" do
    paid = ProductLine.create!(internal_name: "pp", customer_name: "유료 가이드", slug: "paid-dense", introduction: "소개", status: "published")
    paid.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문", status: "published", open_preview: true)
    paid.content_episodes.create!(position: 2, customer_title: "둘째 편", body: "본문", status: "published")
    Commerce::ProductLineSales.set_price!(product_line: paid, total_amount: 1_100, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: paid.reload, actor: @admin)
    member = User.create!(name: "회원", email: "gd-p-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    post user_session_path, params: { user: { email: member.email, password: "password123" } }
    get product_line_path("paid-dense")
    assert_equal [ [ "보기 →", [ "미리 보기" ] ], [ nil, [ "구매 후 보기" ] ] ], phone_cards
  end

  # --- B ---------------------------------------------------------------------------------------------------------

  test "pages with the display face preload Pretendard, and nothing loads Gowun Batang any more" do
    [ root_path, products_path, product_line_path("dense-guide"), product_episode_path("dense-guide", "01") ].each do |path|
      get path
      assert_select FONT, 1, path
      assert_select "link[href*='fonts.googleapis.com']", 0, path
      assert_not_includes response.body, "Gowun", path
    end
    get announcements_path
    assert_select FONT, 0
  end

  test "the face itself: an @font-face for Pretendard 700 with swap, the token and its tracking" do
    css = File.read(Rails.root.join("app/assets/tailwind/application.css"))
    assert_match(/@font-face\s*\{[^}]*font-family:\s*"Pretendard";[^}]*Pretendard-Bold\.subset\.woff2[^}]*font-weight:\s*700;[^}]*font-display:\s*swap;/m, css)
    assert_match(/--font-display:\s*"Pretendard",/, css)
    assert_match(/\.font-display\s*\{\s*letter-spacing:\s*-0\.02em;/, css)
    assert Rails.root.join("app/assets/fonts/Pretendard-Bold.subset.woff2").exist?
    assert Rails.root.join("app/assets/fonts/Pretendard-LICENSE.txt").read.include?("SIL Open Font License")
  end
end
