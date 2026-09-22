require "test_helper"

# Handoff 0065 (decision D5) -- the old Season URLs are permanent redirects to
# the product each Season became. The data is built in the legacy shape and moved
# by SeasonFlatten, exactly as it will be in production.
class LegacySeasonRedirectsTest < ActionDispatch::IntegrationTest
  setup do
    @conn = ActiveRecord::Base.connection
    @line = ProductLine.create!(internal_name: "was-core", customer_name: "제품", slug: "legacy-line", status: "published", introduction: "소개")
    @first = ProductSeason.create!(product_line: @line, internal_name: "S01", season_code: "S01", slug: "first-edition", status: "published", visibility: "public", position: 1)
    @second = ProductSeason.create!(product_line: @line, internal_name: "S02", season_code: "S02", slug: "second-edition", status: "published", visibility: "public", position: 2)
    @first_episode = legacy_episode(@first, 0)
    @second_episode = legacy_episode(@second, 1)
    @asset = ContentAsset.create!(content_episode_id: @first_episode, title: "소스", kind: "소스코드", position: 1,
      file: { io: file_fixture("assets/sample.zip").open, filename: "sample.zip", content_type: "application/zip" })
    SeasonFlatten.run!
  end

  def legacy_episode(season, position)
    now = @conn.quote(Time.current)
    @conn.execute("INSERT INTO content_episodes (product_season_id, position, customer_title, body, status, lock_version, created_at, updated_at) " \
                  "VALUES (#{season.id}, #{position}, #{@conn.quote("편 #{position}")}, #{@conn.quote("본문 #{position}")}, 'published', 0, #{now}, #{now})")
    @conn.select_value("SELECT id FROM content_episodes WHERE product_season_id = #{season.id} AND position = #{position}")
  end

  def assert_permanent_redirect(from, to)
    get from
    assert_response :moved_permanently, "#{from} should be a permanent redirect"
    assert_redirected_to to
  end

  test "an old Season page redirects permanently to the product that Season became" do
    assert_permanent_redirect "/products/legacy-line/first-edition", "/products/legacy-line"
    assert_permanent_redirect "/products/legacy-line/second-edition", "/products/legacy-line-second-edition"
  end

  test "an old Season episode URL redirects to the same episode of the new product, and that page works" do
    assert_permanent_redirect "/products/legacy-line/first-edition/00", "/products/legacy-line/00"
    follow_redirect!
    assert_response :success
    assert_match(/본문 0/, response.body)

    assert_permanent_redirect "/products/legacy-line/second-edition/01", "/products/legacy-line-second-edition/01"
    follow_redirect!
    assert_response :success
    assert_match(/본문 1/, response.body)
  end

  test "an old file download URL redirects to the new download URL and the file is still delivered" do
    assert_permanent_redirect "/products/legacy-line/first-edition/00/assets/#{@asset.id}", "/products/legacy-line/00/assets/#{@asset.id}"
    follow_redirect!
    assert_response :success
    assert_equal file_fixture("assets/sample.zip").binread, response.body.b
  end

  test "the new URLs are served directly, never bounced through the old-URL redirect" do
    get "/products/legacy-line"
    assert_response :success
    get "/products/legacy-line/00"
    assert_response :success
    get "/products/legacy-line-second-edition/01"
    assert_response :success
  end

  test "a redirect never confirms a product a visitor could not open" do
    { "draft" => "public", "unpublished" => "public", "published" => "private" }.each do |status, visibility|
      @conn.execute("UPDATE product_lines SET status = #{@conn.quote(status)}, visibility = #{@conn.quote(visibility)} WHERE legacy_season_id = #{@second.id}")
      [ "/products/legacy-line/second-edition", "/products/legacy-line/second-edition/01" ].each do |url|
        get url
        assert_response :not_found, "#{status}/#{visibility}: #{url}"
      end
    end
  end

  test "unknown Seasons, a Season slug of another product, and unmigrated Seasons are plain 404s" do
    get "/products/legacy-line/nope"
    assert_response :not_found
    get "/products/nope/first-edition"
    assert_response :not_found

    other = ProductLine.create!(internal_name: "o", customer_name: "o", slug: "other-line", status: "published", introduction: "o")
    get "/products/#{other.slug}/first-edition"
    assert_response :not_found

    late = ProductSeason.create!(product_line: @line, internal_name: "S03", season_code: "S03", slug: "third-edition", status: "published")
    get "/products/legacy-line/third-edition"
    assert_response :not_found, "a Season nobody moved has no product to go to"
    assert_not_nil late
  end

  test "a gated product's file is still license-gated after the redirect" do
    prod = Product.create!(code: "legacy_gated", name: "잠금", active: true, sale_enabled: true)
    ProductOffer.new(product: prod, code: "legacy_gated-once", duration_months: nil, currency: "KRW", active: true, discount_bps: 0,
      supply_amount: 0, vat_amount: 0, total_amount: 0, version: 1).save!(validate: false)
    @conn.execute("UPDATE product_lines SET product_id = #{prod.id} WHERE legacy_season_id = #{@first.id}")

    get "/products/legacy-line/first-edition/00/assets/#{@asset.id}"
    assert_response :moved_permanently
    follow_redirect!
    assert_redirected_to new_user_session_path
  end
end
