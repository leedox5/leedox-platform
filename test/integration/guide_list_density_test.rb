require "test_helper"

# Handoff 0104 -- the guide list (/products) on the home / guide page's terms: words kept whole, the display face for
# names, "에피소드 N" (the home's helper), 10px phone margins, no empty filter tabs; on phones a row card (cover left,
# text right) and the title and tabs on one row; no Guides label, no 자세히 보기. The dashboard's cards are unchanged.
class GuideListDensityTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "gl-adm-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @member = User.create!(name: "회원", email: "gl-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    @free = guide!("gl-free", 0, summary: "WSL의 개념부터 Ubuntu 설치, 파일 시스템, VS Code 연동, 네트워크까지 익히는 실전 가이드입니다", published: 2, drafts: 1)
    @empty = guide!("gl-empty", 0, published: 0, drafts: 1)
  end

  def guide!(slug, amount, summary: nil, published: 1, drafts: 0)
    line = ProductLine.create!(internal_name: slug, customer_name: "처음 만난 Claude: 설치부터 내 프로젝트까지 #{slug}", slug: slug,
      summary: summary, introduction: "소개", status: "published")
    published.times { |i| line.content_episodes.create!(position: i + 1, customer_title: "공개 #{i + 1}", body: "본문", status: "published") }
    drafts.times { |i| line.content_episodes.create!(position: 50 + i, customer_title: "예정 #{i + 1}", body: "본문", status: "draft") }
    Commerce::ProductLineSales.set_price!(product_line: line, total_amount: amount, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: line.reload, actor: @admin)
    line.reload
  end

  def sign_in(user) = post(user_session_path, params: { user: { email: user.email, password: "password123" } })
  def card(line) = css_select("main a[href='#{product_line_path(line.slug)}']").first
  def tabs = css_select("nav[aria-label='가이드 필터'] a").map { |a| a.text.squish }
  def classes(node) = node["class"].split

  # --- (가) ----------------------------------------------------------------------------------------------------

  test "names and summaries wrap between words; the name is the display face" do
    get products_path
    name = card(@free).at_css("h2")
    %w[break-keep break-words font-display font-bold].each { |k| assert_includes classes(name), k }
    summary = card(@free).at_css("p")
    %w[break-keep break-words].each { |k| assert_includes classes(summary), k }
  end

  test "the count is the home's label: published episodes only, 공개 예정 when none; no 공개 N편 left on the list" do
    get products_path
    assert_equal "에피소드 2", card(@free).css("span").last.text.strip
    assert_equal "공개 예정", card(@empty).css("span").last.text.strip
    assert_no_match(/공개 \d+편|\d+편/, css_select("main").text)
  end

  test "10px side margins on phones, sm and up as before" do
    get products_path
    %w[px-2.5 pt-4 sm:px-6 sm:py-10].each { |k| assert_includes classes(css_select("main").first), k }
  end

  test "guest: a tab with nothing in it isn't drawn (유료 0); 전체 always; the one you're on even when empty" do
    get products_path
    assert_equal [ "전체 2", "무료 2" ], tabs
    get products_path(filter: "paid")
    assert_equal [ "전체 2", "무료 2", "유료 0" ], tabs
    assert_includes css_select("main").text, "유료 가이드가 아직 없습니다."
  end

  test "member: 내 가이드 only once something is in use; on ?filter=mine even at 0" do
    sign_in(@member)
    get products_path
    assert_equal [ "전체 2", "무료 2" ], tabs
    get products_path(filter: "mine")
    assert_equal [ "전체 2", "무료 2", "내 가이드 0" ], tabs
    post claim_free_access_path(@free.product.code)
    get products_path
    assert_equal [ "전체 2", "무료 2", "내 가이드 1" ], tabs
    paid = guide!("gl-paid", 1_100)
    get products_path
    assert_equal [ "전체 3", "무료 2", "유료 1", "내 가이드 1" ], tabs
    assert card(paid)
  end

  # --- (나) ----------------------------------------------------------------------------------------------------

  test "the head row: no Guides label, the title and the tabs on one wrapping row, the tabs kept right" do
    get products_path
    assert_no_match(/Guides/, css_select("main").text)
    head = css_select("main > div").first
    assert_equal %w[h1 nav], head.element_children.map(&:name)
    %w[flex flex-wrap items-center justify-between gap-x-3 gap-y-2 mb-3.5 sm:mb-8 sm:items-end].each { |k| assert_includes classes(head), k }
    %w[text-2xl sm:text-4xl font-display].each { |k| assert_includes classes(head.at_css("h1")), k }
    %w[ml-auto flex-wrap justify-end gap-1.5 sm:gap-2].each { |k| assert_includes classes(head.at_css("nav")), k }
    tab = head.at_css("nav a")
    %w[px-3 py-[5px] text-[13px] sm:px-4 sm:py-1.5 sm:text-sm].each { |k| assert_includes classes(tab), k }
  end

  test "phones: a row card -- 124x70 cover on the left at the top, then the text; the summary two lines at most below sm" do
    @free.cover_image.attach(io: file_fixture("covers/cover.jpg").open, filename: "c.jpg", content_type: "image/jpeg")
    @free.update!(cover_image_alt: "표지")
    get products_path
    assert_includes classes(css_select("main .grid").first), "gap-2.5"
    link = card(@free)
    %w[flex sm:flex-col].each { |k| assert_includes classes(link), k }
    cover, text = link.element_children
    assert_equal "img", cover.name
    %w[aspect-video w-full object-cover max-sm:w-[124px] max-sm:self-start max-sm:rounded-lg max-sm:my-3 max-sm:ml-3 max-sm:shrink-0].each { |k| assert_includes classes(cover), k }
    %w[min-w-0 flex-1 px-3 py-2.5 sm:p-5].each { |k| assert_includes classes(text), k }
    assert_equal %w[h2 p div], text.element_children.map(&:name)
    %w[text-[15px] leading-[21px] sm:text-lg].each { |k| assert_includes classes(text.at_css("h2")), k }
    summary = classes(text.at_css("p"))
    %w[text-[13px] leading-[19px] max-sm:line-clamp-2].each { |k| assert_includes summary, k }
    assert_not_includes summary, "line-clamp-2", "no limit from sm"
    row = text.element_children.last
    %w[mt-2 flex items-center gap-2 sm:mt-auto sm:pt-4].each { |k| assert_includes classes(row), k }
    badge, count = row.element_children
    assert_equal "무료", badge.text.strip
    %w[max-sm:text-[11px] max-sm:px-[9px] max-sm:py-0.5].each { |k| assert_includes classes(badge), k }
    assert_equal "에피소드 2", count.text.strip
  end

  test "a guide without a cover has the same structure: the placeholder in the same small box" do
    get products_path
    placeholder, text = card(@empty).element_children
    assert_equal "true", placeholder["aria-hidden"]
    %w[aspect-video max-sm:w-[124px] max-sm:self-start max-sm:rounded-lg].each { |k| assert_includes classes(placeholder), k }
    assert_includes classes(placeholder.at_css("span")), "max-sm:text-[22px]"
    assert_equal %w[h2 div], text.element_children.map(&:name), "no summary, no p"
  end

  test "no 자세히 보기; the whole card is still the one link to the guide page" do
    get products_path
    assert_no_match(/자세히 보기/, css_select("main").text)
    [ @free, @empty ].each do |line|
      assert_equal 1, css_select("main a[href='#{product_line_path(line.slug)}']").size
      assert_empty card(line).css("a")
    end
  end

  test "the dashboard keeps its own cards (공개 N편, 자세히 보기) -- out of this handoff" do
    sign_in(@member)
    get dashboard_path
    assert_match(/공개 \d+편/, css_select("main").text)
    assert_match(/자세히 보기 →/, css_select("main").text)
  end
end
