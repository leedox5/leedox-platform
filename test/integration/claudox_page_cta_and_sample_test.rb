require "test_helper"

class ClaudoxPageCtaAndSampleTest < ActionDispatch::IntegrationTest
  test "hero has an immediate scroll-to-pricing CTA next to 읽기 시작하기" do
    get claudox_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    hero = doc.at_css("h1").ancestors("section").first
    hero_links = hero.css("a")

    assert hero_links.any? { |link| link["href"] == claudox_read_path && link.text == "읽기 시작하기" }
    assert hero_links.any? { |link| link["href"] == "#pricing" }, "expected a hero button linking straight to the #pricing section"
  end

  test "no link in the page content points to Chatdox (the sitewide footer's cross-link is out of scope)" do
    get claudox_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    main_content = doc.at_css("main")
    assert_empty main_content.css("a[href='#{chatdox_path}']")
    assert_no_match(/Chatdox 보기/, response.body)
    assert_no_match(/Cross Product/, response.body)
  end

  test "sample content is a single line item inside the included/excluded card, not its own section" do
    get claudox_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    included_card = doc.css("article").find { |article| article.text.include?("포함 항목 / 미포함 항목") }
    assert included_card, "expected the 포함 항목 / 미포함 항목 card"
    assert_match(/샘플: 완성된 챕터 중 \d+개를 가입 없이 바로 읽어볼 수 있습니다/, included_card.text)

    sample_link = included_card.at_css("a")
    assert sample_link, "expected a single sample link inside the card"
    assert_equal "지금 읽어보기 →", sample_link.text
    assert_equal claudox_chapter_path("01"), sample_link["href"]

    # The old dedicated "샘플 콘텐츠" heading/section is gone.
    assert_no_match(/<h2[^>]*>샘플 콘텐츠<\/h2>/, response.body)
  end

  test "existing structure (chapters grid, FAQ, pricing section) is otherwise unaffected" do
    get claudox_path
    assert_response :success

    assert_match(/실제 구성과 목차/, response.body)
    assert_match(/FAQ/, response.body)
    assert_select "#pricing"
  end

  test "hero shows the same free-trial badge as Chatdox/Antigravity, reading its count from guest_chapter_limit (handoff 0044)" do
    get claudox_path
    assert_response :success

    limit = ProductContent.for("claudox").guest_chapter_limit
    doc = Nokogiri::HTML(response.body)
    hero = doc.at_css("h1").ancestors("section").first
    # The request pins this badge's link to the generic /content/claudox/01
    # route (product_chapter_path), not the legacy /claudox/read/01 helper
    # the rest of this page's reader links use -- matches Chatdox/Antigravity's
    # own badges, which use the same generic route.
    badge = hero.css("a").find { |link| link["href"] == product_chapter_path("claudox", "01") }
    assert badge, "expected a hero link to chapter 01"
    assert_match(/🎁\s*#{limit} 챕터 무료 체험 가능/, badge.text)
  end

  test "부록 (특별판) section lists every real appendix chapter, excludes non_chapter_files, and leaves the 완성 20/20 count untouched (handoff 0044)" do
    get claudox_path
    assert_response :success

    source = ProductContent.for("claudox")
    appendix_ids = source.chapters.select { |c| c[:kind] == :appendix }.map { |c| c[:id] }
    assert appendix_ids.any?, "expected this fixture to actually have appendix chapters to assert against"

    doc = Nokogiri::HTML(response.body)
    appendix_section = doc.css("section").find { |s| s.text.include?("부록 (특별판)") }
    assert appendix_section, "expected a 부록 (특별판) section"

    appendix_ids.each do |id|
      chapter = source.find(id)
      # R2-1: displayed title drops the source .md's own "부록. " H1 prefix,
      # since the card already labels itself "부록 NN" -- the raw prefixed
      # title should not appear verbatim (that was the "부록 90 / 부록. 제목"
      # duplication HQ flagged).
      assert chapter[:title].start_with?("부록. "), "fixture assumption: appendix titles carry a 부록. H1 prefix"
      stripped_title = chapter[:title].sub(/\A부록\.\s*/, "")
      assert_match(stripped_title, appendix_section.text)
      assert_no_match(chapter[:title], appendix_section.text)
      assert appendix_section.at_css("a[href='#{product_chapter_path('claudox', id)}']"), "expected a link to appendix chapter #{id}"
    end
    assert_no_match(/97_commands/, appendix_section.text)
    assert_not_includes appendix_ids, "97", "97_commands.md is a non_chapter_file and must not be listed as an appendix chapter"

    # Appendix presence must not inflate the regular-chapter completion count.
    assert_match(/완성 20 \/ 20/, response.body)
  end

  test "부록 chapters stay license-gated for guests even though they're now linked from the page (handoff 0044)" do
    source = ProductContent.for("claudox")
    appendix_id = source.chapters.find { |c| c[:kind] == :appendix }[:id]

    get product_chapter_path("claudox", appendix_id)
    assert_response :redirect
  end

  test "부록 lock badge reflects the same access check as the real reader gate, not a blanket lock (handoff 0044 R2-2)" do
    Commerce::CatalogBootstrap.call!
    source = ProductContent.for("claudox")
    appendix_ids = source.chapters.select { |c| c[:kind] == :appendix }.map { |c| c[:id] }

    get claudox_path
    doc = Nokogiri::HTML(response.body)
    appendix_section = doc.css("section").find { |s| s.text.include?("부록 (특별판)") }
    assert_match(/🔒 잠금/, appendix_section.text)
    assert_no_match(/열람 가능/, appendix_section.text)

    product = Product.find_by!(code: "claudox")
    user = User.create!(name: "라이선스 보유자", email: "claudox-licensed@example.com", password: "password123")
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    License.create!(
      user: user, product: product, source: "paid", status: "active",
      starts_on: today, last_usable_on: today + 30.days,
      access_ends_at: Commerce::PeriodCalculator::KST.local(*(today + 31.days).then { |d| [ d.year, d.month, d.day ] })
    )
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    get claudox_path
    doc = Nokogiri::HTML(response.body)
    appendix_section = doc.css("section").find { |s| s.text.include?("부록 (특별판)") }
    assert_no_match(/🔒 잠금/, appendix_section.text)
    assert_equal appendix_ids.size, appendix_section.text.scan("열람 가능").size
  end
end
