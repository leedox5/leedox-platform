require "test_helper"

# Handoff 0056 R3 -- customer Product -> Season -> Episode navigation and the
# per-level lifecycle gates. Nothing here needs a login: published content of
# the new structure is public until the later commerce round.
class ProductSeasonCustomerTest < ActionDispatch::IntegrationTest
  setup do
    @line = ProductLine.create!(
      internal_name: "내부", customer_name: "결과 중심 제품", slug: "result-line",
      introduction: "소개 문장",
      ai_supporter: "Codex", status: "published"
    )
    @season = @line.product_seasons.create!(
      internal_name: "S01 내부", customer_title: "첫 번째 판", season_code: "S01", slug: "s01",
      status: "published", visibility: "public"
    )
    @ep1 = @season.content_episodes.create!(position: 1, customer_title: "첫 편", body: "# 첫 편\n\n첫 편 본문", status: "published")
    @ep2 = @season.content_episodes.create!(position: 2, customer_title: "둘째 편", body: "# 둘째 편\n\n둘째 편 본문", status: "published")
    @ep1.content_takeaways.create!(kind: "체크리스트", body: "- [ ] 확인하기", position: 1)
  end

  test "product page shows the product info and only published, public seasons" do
    hidden = { "draft-s" => %w[draft public], "unlisted-s" => %w[published unlisted], "private-s" => %w[published private],
               "review-s" => %w[in_review public], "archived-s" => %w[archived public], "unpub-s" => %w[unpublished public] }
    hidden.each_with_index do |(slug, (status, visibility)), i|
      @line.product_seasons.create!(internal_name: "#{slug} 내부", customer_title: "#{slug} 제목", season_code: "X#{i}", slug: slug, status: status, visibility: visibility)
    end

    get product_line_path(@line.slug)
    assert_response :success
    %w[결과\ 중심\ 제품 소개\ 문장 Codex 첫\ 번째\ 판].each { |text| assert_match(text, response.body) }
    assert_no_match(/구매|가격|₩/, css_select("main").text)
    assert_select "a[href=?]", product_season_path(@line.slug, "s01")
    hidden.each_key { |slug| assert_no_match(/#{slug} 제목/, response.body) }
  end

  test "ai_supporter block appears only when set" do
    @line.update!(ai_supporter: nil)
    get product_line_path(@line.slug)
    assert_no_match(/AI 서포터/, response.body)
  end

  test "navigation: Product -> Season -> Episode, with prev/next confined to the season" do
    other = @line.product_seasons.create!(internal_name: "S02", season_code: "S02", slug: "s02", status: "published")
    other.content_episodes.create!(position: 1, customer_title: "다른 시즌 편", status: "published")

    get product_season_path(@line.slug, @season.slug)
    assert_response :success
    assert_match(/첫 편/, response.body)
    assert_match(/둘째 편/, response.body)
    assert_no_match(/다른 시즌 편/, response.body)
    assert_select "a[href=?]", product_season_episode_path(@line.slug, @season.slug, "01")

    get product_season_episode_path(@line.slug, @season.slug, "01")
    assert_response :success
    assert_match(/첫 편 본문/, response.body)
    assert_match(/확인하기/, response.body)
    assert_select "a[href=?]", product_season_episode_path(@line.slug, @season.slug, "02")
    assert_select "a[href=?]", product_season_episode_path(@line.slug, @season.slug, "00"), false

    get product_season_episode_path(@line.slug, @season.slug, "02")
    assert_select "a[href=?]", product_season_episode_path(@line.slug, @season.slug, "01")
    assert_no_match(/다른 시즌 편/, response.body)

    get product_season_episode_path(@line.slug, @season.slug, "1")
    assert_response :success
  end

  test "internal_ref and other episodes' bodies never leak" do
    @ep1.update!(internal_ref: "비공개 출처 메모")
    get product_season_episode_path(@line.slug, @season.slug, "01")
    assert_no_match(/비공개 출처 메모/, response.body)
    assert_no_match(/둘째 편 본문/, response.body)
  end

  test "lifecycle: a non-published product is invisible at every level, even to someone who knows every slug" do
    %w[draft unpublished].each do |status|
      @line.update!(status: status)
      [ product_line_path(@line.slug), product_season_path(@line.slug, @season.slug),
        product_season_episode_path(@line.slug, @season.slug, "01") ].each do |url|
        get url
        assert_response :not_found, "#{status} product exposed #{url}"
      end
    end
  end

  test "lifecycle: a season that is not published or is private 404s on its page and its episodes" do
    { "draft" => "public", "in_review" => "public", "unpublished" => "public", "archived" => "public", "published" => "private" }.each do |status, visibility|
      @season.update!(status: status, visibility: visibility)
      get product_season_path(@line.slug, @season.slug)
      assert_response :not_found, "#{status}/#{visibility} season page exposed"
      get product_season_episode_path(@line.slug, @season.slug, "01")
      assert_response :not_found, "#{status}/#{visibility} season episode exposed"
    end
  end

  test "an unlisted season is reachable by URL but not listed on the product page" do
    @season.update!(visibility: "unlisted")
    get product_line_path(@line.slug)
    assert_no_match(/첫 번째 판/, response.body)
    get product_season_path(@line.slug, @season.slug)
    assert_response :success
    get product_season_episode_path(@line.slug, @season.slug, "01")
    assert_response :success
  end

  test "lifecycle: non-published episodes are absent from the list and 404 on direct URL, and don't break prev/next" do
    %w[draft in_review unpublished archived].each do |status|
      @ep2.update!(status: status)
      get product_season_path(@line.slug, @season.slug)
      assert_no_match(/둘째 편/, response.body, "#{status} episode listed")
      get product_season_episode_path(@line.slug, @season.slug, "02")
      assert_response :not_found, "#{status} episode reachable"
      get product_season_episode_path(@line.slug, @season.slug, "01")
      assert_select "a[href=?]", product_season_episode_path(@line.slug, @season.slug, "02"), false
    end
  end

  test "a season with zero published episodes renders an empty state, not an error" do
    @season.content_episodes.update_all(status: "draft")
    get product_season_path(@line.slug, @season.slug)
    assert_response :success
    assert_match(/아직 공개된 편이 없습니다/, response.body)
  end

  test "unknown slugs and unknown episodes 404 cleanly; a season slug from another product does not resolve" do
    get product_line_path("nope")
    assert_response :not_found
    get product_season_path(@line.slug, "nope")
    assert_response :not_found
    get product_season_episode_path(@line.slug, @season.slug, "99")
    assert_response :not_found

    other_line = ProductLine.create!(internal_name: "o", customer_name: "o", slug: "other-line", introduction: "소개", status: "published")
    get product_season_path(other_line.slug, @season.slug)
    assert_response :not_found
  end

  test "episodes of the legacy bundle path and the season path are separate namespaces" do
    product = Product.create!(code: "content_lab", name: "Content Lab", active: true)
    bundle = ContentBundle.create!(product: product, internal_name: "레거시", slug: "legacy-bundle", status: "published")
    bundle.content_episodes.create!(position: 1, customer_title: "레거시 편", body: "레거시 본문", status: "published")

    get product_season_path(@line.slug, "legacy-bundle")
    assert_response :not_found
    get "/content/content_lab/legacy-bundle"
    assert_response :success
    assert_match(/레거시 편/, response.body)
    assert_no_match(/첫 편/, response.body)
  end
end
