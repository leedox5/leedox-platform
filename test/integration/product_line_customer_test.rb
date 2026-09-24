require "test_helper"

# Handoff 0056 R3 / 0065 -- customer ProductLine -> Episode navigation and the
# per-level lifecycle gates. A product without a commerce Product is free and
# public; the license-gated states live in season_pricing_and_purchase_test
# (now product_line_sales_and_purchase_test).
class ProductLineCustomerTest < ActionDispatch::IntegrationTest
  setup do
    @line = ProductLine.create!(
      internal_name: "내부", customer_name: "결과 중심 제품", slug: "result-line",
      introduction: "소개 문장",
      ai_supporter: "Codex", status: "published"
    )
    @ep1 = @line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "# 첫 편\n\n첫 편 본문", status: "published")
    @ep2 = @line.content_episodes.create!(position: 2, customer_title: "둘째 편", body: "# 둘째 편\n\n둘째 편 본문", status: "published")
    @ep1.content_takeaways.create!(kind: "체크리스트", body: "- [ ] 확인하기", position: 1)
  end

  test "product page shows the product info and the published episodes, with no purchase box for a free product" do
    @line.content_episodes.create!(position: 3, customer_title: "초안 편", status: "draft")

    get product_line_path(@line.slug)
    assert_response :success
    %w[결과\ 중심\ 제품 소개\ 문장 Codex 첫\ 편 둘째\ 편].each { |text| assert_match(text, response.body) }
    assert_no_match(/초안 편/, response.body)
    assert_select "#product-purchase", 0
    assert_no_match(/구매|가격|₩/, css_select("main").text)
    assert_select "a[href=?]", product_episode_path(@line.slug, "01")
  end

  # Handoff 0066: "E01" is display text only; the link (and its digits-only URL segment) is unchanged.
  test "episode cards show an E-prefixed number and a start CTA, while the links keep the plain number" do
    get product_line_path(@line.slug)
    assert_select "ol a[href=?]", product_episode_path(@line.slug, "01") do
      assert_select "span", text: "E01"
      assert_select "span", text: "학습 시작 →"
    end
    assert_select "ol a[href=?] span", product_episode_path(@line.slug, "02"), text: "E02"
    assert_select "ol a[href=?] span.truncate[title=?]", product_episode_path(@line.slug, "01"), "첫 편", text: "첫 편"
    assert_select "ol a span", text: "01", count: 0
    assert_select "ol a", count: 2
    assert_select "ol a[href*='E0']", count: 0
  end

  test "the series label shows only for a product that belongs to a series" do
    get product_line_path(@line.slug)
    assert_select "main > p.uppercase", 0

    @line.update!(series_key: "grp", series_label: "시즌1")
    get product_line_path(@line.slug)
    assert_select "main > p.uppercase", text: "시즌1"
  end

  test "ai_supporter block appears only when set" do
    @line.update!(ai_supporter: nil)
    get product_line_path(@line.slug)
    assert_no_match(/AI 서포터/, response.body)
  end

  test "navigation: product page -> episode, with prev/next inside the product" do
    other = ProductLine.create!(internal_name: "o", customer_name: "다른 제품", slug: "other-line", introduction: "소개", status: "published")
    other.content_episodes.create!(position: 1, customer_title: "다른 제품 편", status: "published")

    get product_line_path(@line.slug)
    assert_no_match(/다른 제품 편/, response.body)

    get product_episode_path(@line.slug, "01")
    assert_response :success
    assert_match(/첫 편 본문/, response.body)
    assert_match(/확인하기/, response.body)
    assert_select "a[href=?]", product_line_path(@line.slug), text: /결과 중심 제품/
    assert_select "a[href=?]", product_episode_path(@line.slug, "02")
    assert_select "a[href=?]", product_episode_path(@line.slug, "00"), false

    get product_episode_path(@line.slug, "02")
    assert_select "a[href=?]", product_episode_path(@line.slug, "01")
    assert_no_match(/다른 제품 편/, response.body)

    get product_episode_path(@line.slug, "1")
    assert_response :success
  end

  test "internal_ref and other episodes' bodies never leak" do
    @ep1.update!(internal_ref: "비공개 출처 메모")
    get product_episode_path(@line.slug, "01")
    assert_no_match(/비공개 출처 메모/, response.body)
    assert_no_match(/둘째 편 본문/, response.body)
  end

  test "lifecycle: a non-published product is invisible at every level, even to someone who knows every slug" do
    %w[draft unpublished].each do |status|
      @line.update!(status: status)
      [ product_line_path(@line.slug), product_episode_path(@line.slug, "01") ].each do |url|
        get url
        assert_response :not_found, "#{status} product exposed #{url}"
      end
    end
  end

  test "reach: a private product 404s on its page and its episodes, unlisted and public are reachable" do
    @line.update!(visibility: "private")
    [ product_line_path(@line.slug), product_episode_path(@line.slug, "01") ].each do |url|
      get url
      assert_response :not_found, "private product exposed #{url}"
    end

    %w[unlisted public].each do |visibility|
      @line.update!(visibility: visibility)
      get product_line_path(@line.slug)
      assert_response :success, visibility
      get product_episode_path(@line.slug, "01")
      assert_response :success, visibility
    end
  end

  test "lifecycle: non-published episodes are absent from the list and 404 on direct URL, and don't break prev/next" do
    %w[draft in_review unpublished archived].each do |status|
      @ep2.update!(status: status)
      get product_line_path(@line.slug)
      assert_no_match(/둘째 편/, response.body, "#{status} episode listed")
      get product_episode_path(@line.slug, "02")
      assert_response :not_found, "#{status} episode reachable"
      get product_episode_path(@line.slug, "01")
      assert_select "a[href=?]", product_episode_path(@line.slug, "02"), false
    end
  end

  test "a product with zero published episodes renders an empty state, not an error" do
    @line.content_episodes.update_all(status: "draft")
    get product_line_path(@line.slug)
    assert_response :success
    assert_match(/준비 중입니다/, response.body)
  end

  test "unknown slugs and unknown episodes 404 cleanly" do
    get product_line_path("nope")
    assert_response :not_found
    get product_episode_path(@line.slug, "99")
    assert_response :not_found
    get product_episode_path("nope", "01")
    assert_response :not_found
  end

  test "episodes of the legacy bundle path and the product path are separate namespaces" do
    product = Product.create!(code: "content_lab", name: "Content Lab", active: true)
    bundle = ContentBundle.create!(product: product, internal_name: "레거시", slug: "legacy-bundle", status: "published")
    bundle.content_episodes.create!(position: 1, customer_title: "레거시 편", body: "레거시 본문", status: "published")

    get "/products/#{@line.slug}/legacy-bundle"
    assert_response :not_found
    get "/content/content_lab/legacy-bundle"
    assert_response :success
    assert_match(/레거시 편/, response.body)
    assert_no_match(/첫 편/, response.body)
  end
end
