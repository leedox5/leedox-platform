require "test_helper"

# Handoff 0056 R3 -- single admin flow for new products:
# ProductLine -> ProductSeason -> Episode, never touching ContentBundle.
class AdminProductLineManagementTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(name: "관리자", email: "product-line-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @user = User.create!(name: "일반유저", email: "product-line-user-#{SecureRandom.hex(3)}@example.com", password: "password123")
  end

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def make_line(overrides = {})
    ProductLine.create!({ internal_name: "내부", customer_name: "고객 제품", slug: "test-line", problem: "p", expected_result: "e", target_audience: "t" }.merge(overrides))
  end

  def make_season(line, overrides = {})
    line.product_seasons.create!({ internal_name: "S01 내부", customer_title: "첫 번째 판", season_code: "S01", slug: "s01" }.merge(overrides))
  end

  test "guests and non-admins cannot reach any product admin URL" do
    line = make_line
    season = make_season(line)

    urls = [ admin_product_lines_path, admin_product_line_path(line), edit_admin_product_line_path(line),
             new_admin_product_line_product_season_path(line), admin_product_season_path(season),
             edit_admin_product_season_path(season), new_admin_product_season_content_episode_path(season) ]

    urls.each do |url|
      get url
      assert_redirected_to new_user_session_path
    end

    sign_in_as(@user)
    urls.each do |url|
      get url
      assert_redirected_to root_path
    end

    assert_no_difference [ "ProductLine.count", "ProductSeason.count", "ContentEpisode.count" ] do
      post admin_product_lines_path, params: { product_line: { internal_name: "x", customer_name: "x", slug: "x", problem: "p", expected_result: "e", target_audience: "t" } }
      post admin_product_line_product_seasons_path(line), params: { product_season: { internal_name: "x", season_code: "S9", slug: "s9" } }
      post admin_product_season_content_episodes_path(season), params: { content_episode: { customer_title: "x", position: 1 } }
    end
  end

  test "full flow: Product -> Season -> Episode with revision, takeaway, transitions, preview and delete -- no Bundle anywhere" do
    sign_in_as(@admin)

    # 1. Product (draft by default)
    post admin_product_lines_path, params: { product_line: {
      internal_name: "R3 내부명", customer_name: "R3 제품", slug: "r3-line", problem: "문제", expected_result: "결과", target_audience: "대상"
    } }
    line = ProductLine.last
    assert_redirected_to edit_admin_product_line_path(line)
    assert_equal "draft", line.status

    # 2. Season under it
    get new_admin_product_line_product_season_path(line)
    assert_response :success
    post admin_product_line_product_seasons_path(line), params: { product_season: {
      internal_name: "R3 S01 내부", customer_title: "R3 첫 판", season_code: "s01", slug: "s01"
    } }
    season = ProductSeason.last
    assert_redirected_to edit_admin_product_season_path(season)
    assert_equal line, season.product_line
    assert_equal "S01", season.season_code

    # 3. Episode created from the Season screen belongs to that Season automatically
    get new_admin_product_season_content_episode_path(season)
    assert_response :success
    assert_no_match(/content_bundle|product_id|묶음/, response.body)
    post admin_product_season_content_episodes_path(season), params: { content_episode: { customer_title: "첫 편", position: 1, body: "# 첫 편\n\n본문 v1" } }
    episode = ContentEpisode.last
    assert_redirected_to edit_admin_content_episode_path(episode)
    assert_equal season, episode.product_season
    assert_nil episode.bundle_id
    assert_equal "draft", episode.status

    get edit_admin_content_episode_path(episode)
    assert_response :success
    assert_select "a[href=?]", edit_admin_product_season_path(season)
    assert_no_match(/묶음으로/, response.body)

    # 4. revision on body change
    patch admin_content_episode_path(episode), params: { content_episode: { customer_title: "첫 편", position: 1, body: "# 첫 편\n\n본문 v2", lock_version: episode.lock_version } }
    assert_equal 1, episode.reload.content_revisions.count
    assert_equal "# 첫 편\n\n본문 v1", episode.content_revisions.first.body_snapshot

    # 5. takeaway
    post admin_content_episode_content_takeaways_path(episode), params: { content_takeaway: { kind: "체크리스트", body: "- [ ] 확인", position: 1 } }
    assert_equal 1, episode.content_takeaways.count

    # 6. admin previews work at every level while everything is still draft
    get admin_product_line_path(line)
    assert_response :success
    assert_match(/R3 제품/, response.body)
    assert_match(/R3 첫 판/, response.body)
    get admin_product_season_path(season)
    assert_response :success
    assert_match(/첫 편/, response.body)
    get admin_content_episode_path(episode)
    assert_response :success
    assert_match(/본문 v2/, response.body)

    # 7. status transitions go through the shared validated path
    patch transition_admin_content_episode_path(episode, status: "in_review")
    assert_equal "in_review", episode.reload.status
    patch transition_admin_content_episode_path(episode, status: "published")
    assert_equal "published", episode.reload.status
    patch transition_admin_content_episode_path(episode, status: "published")
    assert_redirected_to edit_admin_content_episode_path(episode)
    assert_equal "published", episode.reload.status

    # 8. delete returns to the Season, cascading revisions/takeaways
    assert_difference [ "ContentEpisode.count", "ContentRevision.count", "ContentTakeaway.count" ], -1 do
      delete admin_content_episode_path(episode)
    end
    assert_redirected_to edit_admin_product_season_path(season)
    follow_redirect!
    assert_match(/아직 편이 없습니다/, response.body)
  end

  test "the new-product screens never send the author to /admin/content_bundles" do
    sign_in_as(@admin)
    line = make_line
    season = make_season(line)
    episode = season.content_episodes.create!(position: 1, customer_title: "편")

    [ edit_admin_product_line_path(line), admin_product_line_path(line), new_admin_product_line_product_season_path(line),
      edit_admin_product_season_path(season), admin_product_season_path(season),
      new_admin_product_season_content_episode_path(season), edit_admin_content_episode_path(episode),
      admin_content_episode_path(episode) ].each do |url|
      get url
      assert_response :success
      assert_no_match(%r{/admin/content_bundles}, response.body, "#{url} links to the legacy bundle screens")
    end

    # only the list screen carries the clearly-labelled auxiliary legacy link
    get admin_product_lines_path
    assert_match(/기존 DB 콘텐츠 관리/, response.body)
  end

  test "product and season edits persist, including lifecycle state" do
    sign_in_as(@admin)
    line = make_line
    season = make_season(line)

    patch admin_product_line_path(line), params: { product_line: { customer_name: "바뀐 이름", status: "published" } }
    assert_equal "바뀐 이름", line.reload.customer_name
    assert_equal "published", line.status

    patch admin_product_season_path(season), params: { product_season: { status: "published", visibility: "unlisted", customer_title: "바뀐 제목" } }
    assert_equal "published", season.reload.status
    assert_equal "unlisted", season.visibility
    assert_equal "바뀐 제목", season.customer_title
  end

  test "invalid create/update never partially saves" do
    sign_in_as(@admin)
    line = make_line
    make_season(line)

    assert_no_difference [ "ProductLine.count", "ProductSeason.count" ] do
      post admin_product_lines_path, params: { product_line: { internal_name: "", customer_name: "", slug: line.slug, problem: "", expected_result: "", target_audience: "" } }
      assert_response :unprocessable_entity
      post admin_product_line_product_seasons_path(line), params: { product_season: { internal_name: "dup", season_code: "S01", slug: "s01" } }
      assert_response :unprocessable_entity
    end

    season = line.product_seasons.first
    post admin_product_season_content_episodes_path(season), params: { content_episode: { customer_title: "첫 편", position: 1 } }
    assert_equal 1, season.content_episodes.count
    assert_no_difference "ContentEpisode.count" do
      post admin_product_season_content_episodes_path(season), params: { content_episode: { customer_title: "같은 순서", position: 1 } }
      assert_response :unprocessable_entity
    end
  end

  test "legacy bundle authoring is untouched: bundle episodes still create, list and return to the bundle" do
    sign_in_as(@admin)
    bundle = ContentBundle.create!(internal_name: "레거시 묶음")

    get new_admin_content_bundle_content_episode_path(bundle)
    assert_response :success
    assert_match(/묶음으로/, response.body)

    post admin_content_bundle_content_episodes_path(bundle), params: { content_episode: { customer_title: "레거시 편", position: 1, body: "본문" } }
    episode = ContentEpisode.last
    assert_equal bundle, episode.bundle
    assert_nil episode.product_season_id

    delete admin_content_episode_path(episode)
    assert_redirected_to edit_admin_content_bundle_path(bundle)
  end
end
