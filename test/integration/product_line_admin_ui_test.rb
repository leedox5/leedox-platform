require "test_helper"

# Handoff 0056 R6 -- the product-management list: one-line "새 제품" button, clickable large
# cover images linking to the product's admin preview (real image or shared placeholder),
# customer screens unchanged.
class ProductLineAdminUiTest < ActionDispatch::IntegrationTest
  PLACEHOLDER_ALT = "대표 이미지 없음 (기본 이미지)".freeze

  setup do
    @admin = User.create!(name: "관리자", email: "ui-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @user = User.create!(name: "일반유저", email: "ui-user-#{SecureRandom.hex(3)}@example.com", password: "password123")
    @with_cover = ProductLine.create!(internal_name: "a", customer_name: "이미지 있는 제품", slug: "with-cover", introduction: "소개")
    @with_cover.cover_image.attach(io: file_fixture("covers/cover.jpg").open, filename: "hero-shot.jpg", content_type: "image/jpeg")
    @with_cover.update!(cover_image_alt: "실제 대체문구")
    @without = ProductLine.create!(internal_name: "b", customer_name: "이미지 없는 제품", slug: "without-cover", introduction: "소개")
  end

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def assert_no_empty_links
    css_select("main a").each do |a|
      href = a["href"].to_s
      assert href.present? && href != "#" && !href.start_with?("javascript:"), "empty/placeholder link: #{a.to_html[0, 120]}"
    end
    css_select("main img").each { |img| assert img["src"].present?, "img without src" }
  end

  test "the 새 제품 button stays on one line and keeps its target" do
    sign_in_as(@admin)
    get admin_product_lines_path
    assert_response :success
    button = css_select("main header a").find { |a| a.text.include?("새 제품") }
    assert_not_nil button
    assert_equal "+ 새 제품", button.text.strip
    assert_equal new_admin_product_line_path, button["href"]
    classes = button["class"].split
    %w[whitespace-nowrap flex-shrink-0 inline-flex bg-blue-600 px-4 py-2 rounded-lg font-bold].each { |k| assert_includes classes, k }
    assert_includes classes, "self-start"
    assert_includes classes, "sm:self-auto"
    # the text column may shrink; the button may not
    assert_includes css_select("main header > div").first["class"].split, "min-w-0"
  end

  test "list grid: 공개 상태, Season 수 and 관리 stay on one line, and a narrow screen scrolls the table instead of clipping it" do
    sign_in_as(@admin)
    get admin_product_lines_path
    assert_response :success

    headers = css_select("main thead th")
    %w[공개\ 상태 Season\ 수 관리].each do |label|
      th = headers.find { |h| h.text.strip == label }
      assert_not_nil th, "#{label} header missing"
      assert_includes th["class"].split, "whitespace-nowrap", "#{label} header can wrap"
    end
    assert_includes headers.find { |h| h.text.strip == "관리" }["class"].split, "text-right", "alignment must be unchanged"

    css_select("main tbody tr").each do |row|
      cells = row.css("td")
      # status, season count, manage -- the last three cells
      cells.to_a.last(3).each { |td| assert_includes td["class"].split, "whitespace-nowrap", "cell can wrap: #{td.text.strip}" }
      assert_includes cells.last["class"].split, "text-right"
      assert_equal "편집", cells.last.at_css("a").text.strip
    end

    card = css_select("main section").first
    assert_includes card["class"].split, "overflow-x-auto"
    assert_not_includes card["class"].split, "overflow-hidden", "overflow-hidden would clip the table at narrow widths"
    assert_includes css_select("main table").first["class"].split, "min-w-full"
  end

  test "the grid change is scoped to this list: legacy content-bundle list and the season screens keep their own markup" do
    sign_in_as(@admin)
    get admin_content_bundles_path
    assert_includes css_select("main section").first["class"].split, "overflow-hidden"
    get admin_product_lines_path
    assert_no_match(/overflow-hidden/, css_select("main section").first["class"])
  end

  test "other product-management action buttons don't wrap either" do
    sign_in_as(@admin)
    season = @with_cover.product_seasons.create!(internal_name: "S", season_code: "S01", slug: "s01")
    episode = season.content_episodes.create!(position: 1, customer_title: "편")
    { edit_admin_product_line_path(@with_cover) => "+ 새 Season", edit_admin_product_season_path(season) => "+ 새 편",
      edit_admin_content_episode_path(episode) => "+ 업로드" }.each do |url, label|
      get url
      button = css_select("main a").find { |a| a.text.strip == label }
      assert_not_nil button, "#{label} missing on #{url}"
      assert_includes button["class"].split, "whitespace-nowrap"
      assert_includes button["class"].split, "flex-shrink-0"
    end
  end

  test "list and create-screen navigation and access control are unchanged" do
    get admin_product_lines_path
    assert_redirected_to new_user_session_path
    sign_in_as(@user)
    get admin_product_lines_path
    assert_redirected_to root_path
    delete destroy_user_session_path

    sign_in_as(@admin)
    get admin_product_lines_path
    assert_response :success
    assert_select "a[href=?]", edit_admin_product_line_path(@with_cover)
    get new_admin_product_line_path
    assert_response :success
  end

  test "list: every product's image is an ordinary same-tab link to that product's canonical admin preview" do
    sign_in_as(@admin)
    get admin_product_lines_path
    [ @with_cover, @without ].each do |line|
      link = css_select("a[href='#{admin_product_line_path(line)}']").find { |a| a.at_css("img") }
      assert_not_nil link, "no image link for #{line.customer_name}"
      assert_nil link["target"], "must stay in the same tab (normal back-button flow)"
      assert_nil link["data-action"]
      assert_nil link["data-turbo-frame"]
      assert_includes link["aria-label"], line.customer_name
      assert_includes link["aria-label"], "제품 미리보기로 이동"
    end
    assert_select "dialog", 0
    assert_no_match(/lightbox|modal/i, css_select("main").to_html)
    assert_no_empty_links
  end

  test "list: each image links to its own product row, not a neighbour's" do
    sign_in_as(@admin)
    get admin_product_lines_path
    css_select("main tbody tr").each do |row|
      slug = row.at_css("code").text.strip
      line = ProductLine.find_by!(slug: slug)
      hrefs = row.css("a").map { |a| a["href"] }
      assert_includes hrefs, admin_product_line_path(line)
      assert_includes hrefs, edit_admin_product_line_path(line)
      assert_equal 1, hrefs.count { |h| h == admin_product_line_path(line) }, "image link duplicated or missing in #{slug} row"
      other_ids = hrefs.filter_map { |h| h[%r{/admin/product_lines/(\d+)}, 1]&.to_i }.uniq - [ line.id ]
      assert_empty other_ids, "row #{slug} links to another product: #{other_ids.inspect}"
    end
  end

  test "list: a real cover uses its own thumbnail and alt; no cover uses the labelled placeholder" do
    sign_in_as(@admin)
    get admin_product_lines_path
    real = css_select("a[href='#{admin_product_line_path(@with_cover)}'] img").first
    assert_equal "실제 대체문구", real["alt"]
    assert real["src"].start_with?(admin_product_line_cover_image_path(@with_cover, "thumb"))

    dummy = css_select("a[href='#{admin_product_line_path(@without)}'] img").first
    assert_equal PLACEHOLDER_ALT, dummy["alt"]
    assert_match(%r{\A/assets/product_cover_placeholder-[0-9a-f]+\.svg\z}, dummy["src"])
    assert_includes css_select("td").map(&:text).join, "대표 이미지 없음 · 기본 이미지"
    assert_includes dummy["class"].split, "aspect-video"
    assert_equal css_select("a[href='#{admin_product_line_path(@with_cover)}'] img").first["class"].split.sort,
      dummy["class"].split.sort, "real and placeholder must share the same layout classes"
  end

  test "the placeholder asset is served as an SVG image" do
    sign_in_as(@admin)
    get admin_product_lines_path
    src = css_select("img[alt='#{PLACEHOLDER_ALT}']").first["src"]
    get src
    assert_response :success
    assert_equal "image/svg+xml", response.media_type
  end

  test "clicking a real cover lands on that product's admin preview, and back to the list is unchanged" do
    sign_in_as(@admin)
    get admin_product_lines_path
    list_before = css_select("main tbody tr").map { |r| r.at_css("code").text }
    href = css_select("a[href='#{admin_product_line_path(@with_cover)}']").find { |a| a.at_css("img") }["href"]

    get href
    assert_response :success
    assert_equal "이미지 있는 제품", css_select("main h1").first.text.strip
    assert_equal "실제 대체문구", css_select("main img").first["alt"]
    assert css_select("main img").first["src"].start_with?(admin_product_line_cover_image_path(@with_cover, "hero"))
    assert_select "main a[href=?]", edit_admin_product_line_path(@with_cover)
    assert_select "a[href=?]", admin_product_lines_path, text: /목록|제품/ if css_select("a[href='#{admin_product_lines_path}']").any?

    get admin_product_lines_path
    assert_response :success
    assert_equal list_before, css_select("main tbody tr").map { |r| r.at_css("code").text }
    assert_select "img[src^=?]", admin_product_line_cover_image_path(@with_cover, "thumb")
  end

  test "clicking the placeholder lands on the same product's admin preview" do
    sign_in_as(@admin)
    get admin_product_lines_path
    href = css_select("img[alt='#{PLACEHOLDER_ALT}']").first.ancestors("a").first["href"]
    assert_equal admin_product_line_path(@without), href

    get href
    assert_response :success
    assert_equal "이미지 없는 제품", css_select("main h1").first.text.strip
    assert_includes css_select("main").text, "대표 이미지 없음 · 기본 이미지"
    assert_select "main img[alt='#{PLACEHOLDER_ALT}']", 1
  end

  test "the admin preview destination works for draft, unpublished and published products; unknown ids 404; admin-only" do
    sign_in_as(@admin)
    %w[draft unpublished published].each do |status|
      @with_cover.update!(status: status)
      get admin_product_line_path(@with_cover)
      assert_response :success, "#{status} product preview failed"
    end
    get admin_product_line_path(0)
    assert_response :not_found

    delete destroy_user_session_path
    get admin_product_line_path(@with_cover)
    assert_redirected_to new_user_session_path
    sign_in_as(@user)
    get admin_product_line_path(@with_cover)
    assert_redirected_to root_path
  end

  test "the earlier enlarge-image page no longer exists" do
    sign_in_as(@admin)
    assert_not Rails.application.routes.url_helpers.respond_to?(:admin_product_line_cover_preview_path)
    get "/admin/product_lines/#{@with_cover.id}/cover_preview"
    assert_response :not_found
    get admin_product_lines_path
    assert_no_match(/cover_preview/, response.body)
  end

  test "edit screen: the stored image and the placeholder both link (same tab) to the product's admin preview" do
    sign_in_as(@admin)
    get edit_admin_product_line_path(@with_cover)
    link = css_select("a[href='#{admin_product_line_path(@with_cover)}']").find { |a| a.at_css("img") }
    assert_equal "실제 대체문구", link.at_css("img")["alt"]
    assert_nil link["target"]
    assert_select "img[alt='#{PLACEHOLDER_ALT}']", 0
    assert_includes css_select("main").text, "제품의 미리보기로 이동합니다"
    assert_no_empty_links

    get edit_admin_product_line_path(@without)
    link = css_select("a[href='#{admin_product_line_path(@without)}']").find { |a| a.at_css("img") }
    assert_equal PLACEHOLDER_ALT, link.at_css("img")["alt"]
    assert_nil link["target"]
    assert_includes css_select("main").text, "대표 이미지 없음 · 기본 이미지"
    assert_select "input[type=file][name='product_line[cover_image]']", 1
    assert_no_empty_links
  end

  test "the create screen has no preview link (nothing to preview yet) and no placeholder" do
    sign_in_as(@admin)
    get new_admin_product_line_path
    assert_select "a[href*='/admin/product_lines/'] img", 0
    assert_select "img", 0
  end

  test "on the preview page itself the image is shown without a self-link; no image keeps the labelled placeholder in the same slot" do
    sign_in_as(@admin)
    get admin_product_line_path(@with_cover)
    assert_select "main img[alt='실제 대체문구']", 1
    assert css_select("main a").none? { |a| a.at_css("img") }, "image must not link to the page it is on"

    get admin_product_line_path(@without)
    assert_select "main img[alt='#{PLACEHOLDER_ALT}']", 1
    assert css_select("main a").none? { |a| a.at_css("img") }
    assert_includes css_select("main").text, "대표 이미지 없음 · 기본 이미지"
    kids = css_select("main").first.element_children.reject { |el| el.text.include?("관리자 전용 미리보기") }
    assert_equal "h1", kids[0].name
    assert kids[1].at_css("img"), "placeholder must sit right after the name"
    assert_no_empty_links
  end

  test "customer screens are unchanged: no placeholder, no admin links, no image slot for a product without a cover" do
    @with_cover.update!(status: "published")
    @without.update!(status: "published")

    get product_line_path(@without.slug)
    assert_response :success
    assert_select "img", 0
    assert_no_match(/product_cover_placeholder|cover_preview|기본 이미지/, response.body)

    get product_line_path(@with_cover.slug)
    assert_select "main img[alt='실제 대체문구']", 1
    assert_select "a[href*='cover_preview']", 0
    assert_select "a[href*='/admin/']", 0
    assert_match(%r{\A/product-covers/with-cover/hero\?v=\d+\z}, css_select("main img").first["src"])

    get product_cover_path(@with_cover.slug, "hero")
    assert_response :success
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    @with_cover.update!(status: "draft")
    get product_cover_path(@with_cover.slug, "hero")
    assert_response :not_found
    get product_line_path(@with_cover.slug)
    assert_response :not_found
  end
end
