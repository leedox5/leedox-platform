require "test_helper"

# Handoff 0056 R5 -- customer Hero, image delivery gate, fallback.
class ProductLineCoverCustomerTest < ActionDispatch::IntegrationTest
  setup do
    @line = ProductLine.create!(internal_name: "A", customer_name: "결과 제품", slug: "result-line", problem: "해결할 문제 문장",
      expected_result: "기대 결과 문장", target_audience: "대상", status: "published")
    @line.cover_image.attach(io: file_fixture("covers/cover.jpg").open, filename: "secret-original-name.jpg", content_type: "image/jpeg")
    @line.update!(cover_image_alt: "코드가 완성되는 화면")
  end

  def other_line(cover: false, status: "published")
    line = ProductLine.create!(internal_name: "B", customer_name: "다른 제품", slug: "other-line", problem: "p", expected_result: "e", target_audience: "t", status: status)
    if cover
      line.cover_image.attach(io: file_fixture("covers/cover.png").open, filename: "other.png", content_type: "image/png")
      line.update!(cover_image_alt: "다른 이미지")
    end
    line
  end

  test "Hero: image with the stored alt text, responsive attributes, and the key text together" do
    get product_line_path(@line.slug)
    assert_response :success
    assert_select "img[alt='코드가 완성되는 화면']" do |imgs|
      img = imgs.first
      assert_equal "1600", img["width"]
      assert_equal "900", img["height"]
      assert_includes img["class"], "aspect-video"
      assert_includes img["class"], "object-cover"
      assert_includes img["class"], "w-full"
      assert_match(/480w/, img["srcset"])
      assert_match(/1600w/, img["srcset"])
      assert_match(/100vw/, img["sizes"])
      assert_equal "high", img["fetchpriority"]
      assert_match(%r{\A/product-covers/result-line/hero\?v=\d+\z}, img["src"])
    end
    main = css_select("main").text
    %w[결과\ 제품 해결할\ 문제\ 문장 기대\ 결과\ 문장].each { |text| assert_includes main, text }
  end

  # Character offsets of each landmark inside <main>, so the test can assert document order.
  def landmark_order(html_main, landmarks)
    landmarks.map { |name, needle| [ name, html_main.index(needle) ] }
  end

  def assert_single_column_order(main_html, with_image:, with_ai: true)
    landmarks = [ [ :name, "<h1" ] ]
    landmarks << [ :image, "<img" ] if with_image
    landmarks += [ [ :problem, "해결할 문제" ], [ :result, "기대 결과" ], [ :audience, "대상 고객" ] ]
    landmarks << [ :ai, "AI 서포터" ] if with_ai
    landmarks << [ :season, "Season" ]

    positions = landmark_order(main_html, landmarks)
    missing = positions.select { |_, pos| pos.nil? }.map(&:first)
    assert_empty missing, "landmarks missing from <main>: #{missing.inspect}"
    assert_equal positions.sort_by(&:last).map(&:first), positions.map(&:first), "wrong order: #{positions.inspect}"
  end

  test "Hero is one vertical flow: name, image, problem, result, audience, AI supporter, Seasons" do
    @line.product_seasons.create!(internal_name: "S", customer_title: "첫 판", season_code: "S01", slug: "s01", status: "published", visibility: "public")
    @line.update!(ai_supporter: "Codex")
    get product_line_path(@line.slug)
    assert_single_column_order(css_select("main").to_html, with_image: true)
  end

  test "the Hero never goes back to two columns, at any breakpoint" do
    get product_line_path(@line.slug)
    assert_select "main section.grid", 0
    assert_no_match(/grid-cols-2|md:order-last|md:items-center/, css_select("main").to_html)
    assert_select "main > h1", 1
  end

  test "the image sits directly between the name and the problem, full body width, 16:9" do
    get product_line_path(@line.slug)
    kids = css_select("main").first.element_children
    assert_equal "h1", kids[0].name
    assert_equal "div", kids[1].name
    assert kids[1].at_css("img[alt='코드가 완성되는 화면']"), "image must follow the name"
    assert_includes kids[2].text, "해결할 문제"
    assert_includes css_select("main img").first["class"], "aspect-video"
    assert_includes css_select("main img").first["class"], "w-full"
    assert_equal "(min-width: 824px) 768px, 100vw", css_select("main img").first["sizes"]
  end

  test "without an image the text follows the name directly, in the same order, with no empty media block" do
    plain = other_line
    plain.update!(ai_supporter: "Claude")
    get product_line_path(plain.slug)
    assert_single_column_order(css_select("main").to_html, with_image: false)
    kids = css_select("main").first.element_children
    assert_equal "h1", kids[0].name
    assert_includes kids[1].text, "해결할 문제"
    assert_select "main img", 0
  end

  test "the admin preview uses the same order for a draft product, with and without an image" do
    admin = User.create!(name: "관리자", email: "hero-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }
    @line.update!(status: "draft", ai_supporter: "Codex")
    @line.product_seasons.create!(internal_name: "S", customer_title: "첫 판", season_code: "S01", slug: "s01")

    get admin_product_line_path(@line)
    assert_response :success
    assert_single_column_order(css_select("main").to_html, with_image: true)
    assert_select "main section.grid", 0
    assert_select "main img[alt='코드가 완성되는 화면']", 1

    plain = other_line(status: "draft")
    get admin_product_line_path(plain)
    # admin preview shows the shared placeholder (R6) in the image slot, so the order still has an image
    assert_single_column_order(css_select("main").to_html, with_image: true, with_ai: false)
    assert_select "main img[alt='대표 이미지 없음 (기본 이미지)']", 1
  end

  test "no blob URL, original filename or Active Storage path appears on the page" do
    get product_line_path(@line.slug)
    assert_no_match(%r{rails/active_storage|/blobs/|secret-original-name}, response.body)
    assert_no_match(/#{Regexp.escape(@line.cover_image.blob.key)}/, response.body)
  end

  test "a product without an image renders a clean text Hero -- no img, no empty media area" do
    plain = other_line
    get product_line_path(plain.slug)
    assert_response :success
    assert_select "img", 0
    assert_select "section.grid", 0
    assert_includes css_select("main").text, "다른 제품"
    assert_no_match(/product-covers/, response.body)
  end

  test "published product: hero and thumb variants are served inline as WebP with safe headers" do
    %w[hero thumb].each do |variant|
      get product_cover_path(@line.slug, variant)
      assert_response :success
      assert_equal "image/webp", response.media_type
      assert_match(/\Ainline/, response.headers["Content-Disposition"].to_s)
      assert_equal "nosniff", response.headers["X-Content-Type-Options"]
      cache_control = response.headers["Cache-Control"]
      assert_includes cache_control, "private"
      assert_includes cache_control, "max-age=300"
      assert_not_includes cache_control, "public"
      assert response.headers["ETag"].present?
      dims = Vips::Image.new_from_buffer(response.body, "")
      assert_equal (variant == "hero" ? [ 1600, 900 ] : [ 480, 270 ]), [ dims.width, dims.height ]
    end
  end

  test "the served bytes are the re-encoded variant, never the uploaded original" do
    original = file_fixture("covers/cover.jpg").binread
    get product_cover_path(@line.slug, "hero")
    assert_not_equal original, response.body.b
    assert_equal "RIFF", response.body.b[0, 4]
    assert_equal "WEBP", response.body.b[8, 4]
  end

  test "an unchanged image revalidates with 304" do
    get product_cover_path(@line.slug, "hero")
    etag = response.headers["ETag"]
    get product_cover_path(@line.slug, "hero"), headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  test "draft and unpublished products: the image URL is 404 even though the slug is known" do
    %w[draft unpublished].each do |status|
      @line.update!(status: status)
      %w[hero thumb].each do |variant|
        get product_cover_path(@line.slug, variant)
        assert_response :not_found, "#{status} product #{variant} image reachable"
      end
      get product_line_path(@line.slug)
      assert_response :not_found
    end
  end

  test "unknown variants (incl. 'original'), unknown slugs and products without a cover are 404" do
    get product_cover_path(@line.slug, "original")
    assert_response :not_found
    get product_cover_path(@line.slug, "full")
    assert_response :not_found
    get product_cover_path("no-such-line", "hero")
    assert_response :not_found
    get product_cover_path(other_line.slug, "hero")
    assert_response :not_found
  end

  test "an image can't be reached through another product's slug, and each slug serves only its own image" do
    other = other_line(cover: true)
    get product_cover_path(@line.slug, "hero")
    mine = response.body.b
    get product_cover_path(other.slug, "hero")
    theirs = response.body.b
    assert_not_equal mine, theirs

    other.update!(status: "draft")
    get product_cover_path(other.slug, "hero")
    assert_response :not_found
    get product_cover_path(@line.slug, "hero")
    assert_equal mine, response.body.b
  end

  test "Active Storage's own routes stay disabled" do
    blob = @line.cover_image.blob
    [ "/rails/active_storage/blobs/redirect/#{blob.signed_id}/x.jpg", "/rails/active_storage/blobs/proxy/#{blob.signed_id}/x.jpg",
      "/rails/active_storage/representations/redirect/#{blob.signed_id}/x/x.jpg" ].each do |url|
      get url
      assert_response :not_found
    end
  end

  test "the cover route can't shadow or be shadowed by Season/Episode URLs" do
    season = @line.product_seasons.create!(internal_name: "S", season_code: "S01", slug: "cover", status: "published", visibility: "public")
    season.content_episodes.create!(position: 1, customer_title: "편", status: "published", body: "본문")
    get product_season_path(@line.slug, "cover")
    assert_response :success
    get product_season_episode_path(@line.slug, "cover", "01")
    assert_response :success
    get product_cover_path(@line.slug, "hero")
    assert_equal "image/webp", response.media_type
  end

  test "R4 downloads, Season/Episode pages and legacy bundle URLs are unaffected" do
    season = @line.product_seasons.create!(internal_name: "S", customer_title: "첫 판", season_code: "S01", slug: "s01", status: "published", visibility: "public")
    episode = season.content_episodes.create!(position: 1, customer_title: "첫 편", body: "# 첫 편\n\n본문", status: "published")
    asset = episode.content_assets.create!(title: "소스", kind: "소스코드", position: 1,
      file: { io: file_fixture("assets/sample.zip").open, filename: "sample.zip", content_type: "application/zip" })

    get product_season_episode_path(@line.slug, "s01", "01")
    assert_response :success
    assert_select "h2", text: "이 편의 실전 자료"
    get product_season_episode_asset_path(@line.slug, "s01", "01", asset.id)
    assert_response :success
    assert_match(/\Aattachment;/, response.headers["Content-Disposition"])
    get product_season_path(@line.slug, "s01")
    assert_select "h2", text: "Season 산출물"

    product = Product.create!(code: "content_lab", name: "Content Lab", active: true)
    bundle = ContentBundle.create!(product: product, internal_name: "레거시", slug: "legacy", status: "published")
    bundle.content_episodes.create!(position: 1, customer_title: "레거시 편", status: "published")
    get "/content/content_lab/legacy"
    assert_response :success
  end

  test "no controller serving covers uses ActionController::Live" do
    [ ProductCoversController, Admin::ProductLineCoversController, Admin::ProductLinesController, ProductLinesController ].each do |controller|
      assert_not controller.include?(ActionController::Live)
    end
    get product_cover_path(@line.slug, "hero")
    assert_equal "SAMEORIGIN", response.headers["X-Frame-Options"]
  end
end
