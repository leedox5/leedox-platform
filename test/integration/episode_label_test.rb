require "test_helper"

# Handoff 0056 R4 follow-up -- the new-product structure says "Episode";
# legacy Bundle content and the file-based products keep "Chapter". The
# label depends on the episode's parent, so pin both directions.
class EpisodeLabelTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(name: "관리자", email: "label-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)

    @line = ProductLine.create!(internal_name: "A", customer_name: "제품", slug: "label-line", problem: "p", expected_result: "e", target_audience: "t", status: "published")
    @season = @line.product_seasons.create!(internal_name: "S01", customer_title: "첫 판", season_code: "S01", slug: "s01", status: "published", visibility: "public")
    @season_episode = @season.content_episodes.create!(position: 1, customer_title: "시즌 편", body: "본문", status: "published")

    @product = Product.create!(code: "content_lab", name: "Content Lab", active: true)
    @bundle = ContentBundle.create!(product: @product, internal_name: "레거시", slug: "legacy", status: "published")
    @bundle_episode = @bundle.content_episodes.create!(position: 1, customer_title: "레거시 편", body: "본문", status: "published")
  end

  def sign_in_admin
    post user_session_path, params: { user: { email: @admin.email, password: "password123" } }
  end

  def episode_label
    css_select("p.uppercase.text-blue-600").first&.text&.strip
  end

  test "admin preview labels a Season episode 'Episode' and a Bundle episode 'Chapter'" do
    sign_in_admin

    get admin_content_episode_path(@season_episode)
    assert_response :success
    assert_equal "Episode 1", episode_label
    assert_no_match(/Chapter/i, css_select("main").text)

    get admin_content_episode_path(@bundle_episode)
    assert_response :success
    assert_equal "Chapter 1", episode_label
    assert_no_match(/Episode/, css_select("main").text)
  end

  test "customer Season episode says 'Episode', the legacy Bundle episode still says 'Chapter'" do
    get product_season_episode_path(@line.slug, @season.slug, "01")
    assert_response :success
    assert_equal "Episode 01", episode_label
    assert_no_match(/Chapter/i, css_select("main").text)

    get "/content/content_lab/legacy/01"
    assert_redirected_to new_user_session_path # legacy DB content is license-gated; label checked below with a license
    user = User.create!(name: "유저", email: "label-user-#{SecureRandom.hex(3)}@example.com", password: "password123")
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    License.create!(user: user, product: @product, source: "paid", status: "active", starts_on: today, last_usable_on: today + 30,
      access_ends_at: Commerce::PeriodCalculator::KST.local((today + 31).year, (today + 31).month, (today + 31).day))
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    get "/content/content_lab/legacy/01"
    assert_response :success
    assert_equal "Chapter 01", episode_label
  end

  test "no other new-product screen says 'Chapter'" do
    sign_in_admin
    @season_episode.content_takeaways.create!(kind: "체크리스트", body: "- [ ] a", position: 1)

    [ admin_product_lines_path, admin_product_line_path(@line), edit_admin_product_line_path(@line),
      admin_product_season_path(@season), edit_admin_product_season_path(@season),
      new_admin_product_season_content_episode_path(@season), edit_admin_content_episode_path(@season_episode) ].each do |url|
      get url
      assert_response :success
      assert_no_match(/chapter/i, css_select("main").text, "#{url} shows 'Chapter'")
    end

    delete destroy_user_session_path
    [ product_line_path(@line.slug), product_season_path(@line.slug, @season.slug) ].each do |url|
      get url
      assert_no_match(/chapter/i, css_select("main").text, "#{url} shows 'Chapter'")
    end
  end
end
