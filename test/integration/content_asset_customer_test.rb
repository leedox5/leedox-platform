require "test_helper"

# Handoff 0056 R4 -- customer "이 편의 실전 자료", Season 산출물, and the
# download gate that must hold at every level of the hierarchy.
class ContentAssetCustomerTest < ActionDispatch::IntegrationTest
  setup do
    @line = ProductLine.create!(internal_name: "A", customer_name: "결과 제품", slug: "result-line", problem: "p", expected_result: "e", target_audience: "t", status: "published")
    @season = @line.product_seasons.create!(internal_name: "S01", customer_title: "첫 판", season_code: "S01", slug: "s01", status: "published", visibility: "public")
    @ep1 = @season.content_episodes.create!(position: 1, customer_title: "첫 편", body: "# 첫 편\n\n본문", status: "published")
    @ep2 = @season.content_episodes.create!(position: 2, customer_title: "마지막 편", body: "# 마지막 편\n\n본문", status: "published")
    @a1 = attach(@ep1, "sample.zip", title: "1편 소스", kind: "소스코드", description: "1편 설명", position: 1)
    @a1b = attach(@ep1, "sample.pdf", title: "1편 스펙", kind: "구현 스펙", position: 2, type: "application/pdf")
    @a2 = attach(@ep2, "sample.war", title: "최종 WAR", kind: "실행파일", position: 1)
    @ep1.content_takeaways.create!(kind: "체크리스트", body: "- [ ] 확인", position: 1)
  end

  def attach(episode, name, title:, kind:, position:, description: nil, type: "application/zip", filename: name)
    episode.content_assets.create!(title: title, kind: kind, description: description, position: position,
      file: { io: file_fixture("assets/#{name}").open, filename: filename, content_type: type })
  end

  def dl(episode, asset, season: @season, line: @line)
    product_season_episode_asset_path(line.slug, season.slug, episode.display_id, asset.id)
  end

  test "episode page groups takeaways and files under '이 편의 실전 자료'" do
    get product_season_episode_path(@line.slug, @season.slug, "01")
    assert_response :success
    assert_select "h2", text: "이 편의 실전 자료", count: 1
    assert_match(/체크리스트/, response.body)
    %w[1편\ 소스 1편\ 설명 1편\ 스펙 소스코드 구현\ 스펙 sample.zip sample.pdf].each { |text| assert_match(text, response.body) }
    assert_no_match(/최종 WAR/, response.body)
    assert_select "a[href=?]", dl(@ep1, @a1)
    assert_select "a[href=?]", dl(@ep1, @a1b)
  end

  test "the section is absent when an episode has neither takeaways nor files" do
    @ep1.content_takeaways.destroy_all
    @ep1.content_assets.destroy_all
    get product_season_episode_path(@line.slug, @season.slug, "01")
    assert_no_match(/이 편의 실전 자료/, response.body)
  end

  test "a files-only episode still shows the section" do
    @ep1.content_takeaways.destroy_all
    get product_season_episode_path(@line.slug, @season.slug, "01")
    assert_select "h2", text: "이 편의 실전 자료"
  end

  test "season page collects published episodes' files in episode then asset order, with the original episode title" do
    get product_season_path(@line.slug, @season.slug)
    assert_response :success
    assert_select "h2", text: "Season 산출물"
    titles = css_select("section p.mt-1.font-bold").map { |n| n.text.strip }
    assert_equal [ "1편 소스", "1편 스펙", "최종 WAR" ], titles
    assert_match(/01 첫 편/, response.body)
    assert_match(/02 마지막 편/, response.body)
    assert_select "a[href=?]", dl(@ep2, @a2)
  end

  test "season page omits draft episodes' files and shows no empty section without any files" do
    @ep2.update!(status: "draft")
    get product_season_path(@line.slug, @season.slug)
    assert_no_match(/최종 WAR/, response.body)

    ContentAsset.destroy_all
    get product_season_path(@line.slug, @season.slug)
    assert_no_match(/Season 산출물/, response.body)
  end

  test "the product page never lists files" do
    get product_line_path(@line.slug)
    assert_response :success
    assert_no_match(/산출물|다운로드|1편 소스/, css_select("main").text)
  end

  test "published hierarchy: download succeeds as an attachment with the exact bytes" do
    get dl(@ep1, @a1)
    assert_response :success
    assert_match(/\Aattachment;/, response.headers["Content-Disposition"])
    assert_equal file_fixture("assets/sample.zip").binread, response.body.b
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]

    get dl(@ep1, @a1b)
    assert_response :success
    assert_match(/\Aattachment;/, response.headers["Content-Disposition"], "PDF must not be served inline")
    get dl(@ep2, @a2)
    assert_response :success
  end

  test "an unlisted season's files are reachable by URL, like its episodes" do
    @season.update!(visibility: "unlisted")
    get dl(@ep1, @a1)
    assert_response :success
  end

  test "non-published episodes: files are gone from pages and undownloadable by direct URL" do
    %w[draft in_review unpublished archived].each do |status|
      @ep1.update!(status: status)
      get dl(@ep1, @a1)
      assert_response :not_found, "#{status} episode file downloadable"
      get product_season_path(@line.slug, @season.slug)
      assert_no_match(/1편 소스/, response.body)
    end
  end

  test "season gates: draft, in_review, unpublished, archived and private seasons block downloads" do
    { "draft" => "public", "in_review" => "public", "unpublished" => "public", "archived" => "public", "published" => "private" }.each do |status, visibility|
      @season.update!(status: status, visibility: visibility)
      get dl(@ep1, @a1)
      assert_response :not_found, "#{status}/#{visibility} season file downloadable"
    end
  end

  test "product gates: draft and unpublished products block downloads" do
    %w[draft unpublished].each do |status|
      @line.update!(status: status)
      get dl(@ep1, @a1)
      assert_response :not_found, "#{status} product file downloadable"
    end
  end

  test "an asset id can't be combined with another episode, season or product" do
    get dl(@ep2, @a1)
    assert_response :not_found

    other_season = @line.product_seasons.create!(internal_name: "S02", season_code: "S02", slug: "s02", status: "published", visibility: "public")
    other_ep = other_season.content_episodes.create!(position: 1, customer_title: "다른 시즌 편", status: "published")
    get product_season_episode_asset_path(@line.slug, other_season.slug, other_ep.display_id, @a1.id)
    assert_response :not_found

    other_line = ProductLine.create!(internal_name: "B", customer_name: "B", slug: "other-line", problem: "p", expected_result: "e", target_audience: "t", status: "published")
    get product_season_episode_asset_path(other_line.slug, @season.slug, "01", @a1.id)
    assert_response :not_found

    get product_season_episode_asset_path(@line.slug, @season.slug, "01", 0)
    assert_response :not_found
    get product_season_episode_asset_path(@line.slug, @season.slug, "01", "abc")
    assert_response :not_found
    get product_season_episode_asset_path(@line.slug, @season.slug, "99", @a1.id)
    assert_response :not_found
  end

  test "a legacy bundle episode's file can't be reached through any customer path" do
    bundle = ContentBundle.create!(internal_name: "레거시")
    legacy_episode = bundle.content_episodes.create!(position: 1, customer_title: "레거시", status: "published")
    stray = attach(legacy_episode, "sample.zip", title: "레거시 파일", kind: "k", position: 1)
    get product_season_episode_asset_path(@line.slug, @season.slug, "01", stray.id)
    assert_response :not_found
  end

  test "no Active Storage blob URL is rendered, and Active Storage's own routes are gone" do
    [ product_season_episode_path(@line.slug, @season.slug, "01"), product_season_path(@line.slug, @season.slug) ].each do |url|
      get url
      assert_no_match(%r{rails/active_storage|/blobs/}, response.body)
    end

    blob = @a1.file.blob
    [ "/rails/active_storage/blobs/redirect/#{blob.signed_id}/sample.zip",
      "/rails/active_storage/blobs/proxy/#{blob.signed_id}/sample.zip",
      "/rails/active_storage/disk/anything/sample.zip" ].each do |url|
      get url
      assert_response :not_found, "#{url} is routable"
    end
  end

  test "a hostile original filename is sanitized in the download header" do
    evil = attach(@ep2, "sample.zip", title: "악성 이름", kind: "k", position: 2, filename: "../../etc/pass\"wd\r\nX-Injected: 1;.zip")
    get dl(@ep2, evil)
    assert_response :success
    header = response.headers["Content-Disposition"]
    assert_match(/\Aattachment;/, header)
    assert_no_match(/[\r\n]/, header)
    assert_nil response.headers["X-Injected"]
    assert_no_match(%r{\.\./}, header)
    assert_not_includes header, "etc/pass"
    assert_no_match(/\.\.\//, evil.file.blob.key, "stored key must not derive from the filename")
  end

  test "the page escapes a hostile filename and title" do
    evil = attach(@ep2, "sample.zip", title: "<script>alert(1)</script>", kind: "<b>k</b>", position: 2, filename: "<img src=x onerror=alert(1)>.zip")
    get product_season_episode_path(@line.slug, @season.slug, "02")
    assert_no_match(/<script>alert\(1\)/, response.body)
    assert_no_match(/<img src=x onerror/, response.body)
    assert_match(/&lt;script&gt;/, response.body)
    assert evil.persisted?
  end

  test "no controller here uses ActionController::Live (it breaks Devise's sign-in redirect and drops default security headers)" do
    [ ProductLinesController, ProductAssetDownloadsController, Admin::ContentAssetsController,
      Admin::ContentAssetDownloadsController, Admin::ContentEpisodesController ].each do |controller|
      assert_not controller.include?(ActionController::Live), "#{controller} must not include ActionController::Live"
    end
  end

  test "download responses carry safe, non-cacheable headers and the exact length" do
    get dl(@ep1, @a1)
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal file_fixture("assets/sample.zip").size.to_s, response.headers["Content-Length"]
    assert_equal "application/zip", response.headers["Content-Type"]
    assert_equal %("#{@a1.file.blob.checksum}"), response.headers["ETag"]
  end

  test "ordinary pages keep default security headers" do
    get product_season_episode_path(@line.slug, @season.slug, "01")
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "SAMEORIGIN", response.headers["X-Frame-Options"]
  end

  test "R3 customer URLs and the legacy bundle URLs are unaffected" do
    get product_season_episode_path(@line.slug, @season.slug, "02")
    assert_response :success
    assert_select "a[href=?]", product_season_episode_path(@line.slug, @season.slug, "01")

    product = Product.create!(code: "content_lab", name: "Content Lab", active: true)
    bundle = ContentBundle.create!(product: product, internal_name: "레거시", slug: "legacy", status: "published")
    bundle.content_episodes.create!(position: 1, customer_title: "레거시 편", status: "published")
    get "/content/content_lab/legacy"
    assert_response :success
    assert_no_match(/이 편의 실전 자료/, response.body)
  end
end
