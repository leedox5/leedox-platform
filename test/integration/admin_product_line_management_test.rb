require "test_helper"

# Handoff 0056 R3 -- single admin flow for new products:
# ProductLine -> Episode (no Season since handoff 0065), never touching ContentBundle.
class AdminProductLineManagementTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(name: "관리자", email: "product-line-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @user = User.create!(name: "일반유저", email: "product-line-user-#{SecureRandom.hex(3)}@example.com", password: "password123")
  end

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def make_line(overrides = {})
    ProductLine.create!({ internal_name: "내부", customer_name: "고객 제품", slug: "test-line", introduction: "소개" }.merge(overrides))
  end

  test "guests and non-admins cannot reach any product admin URL" do
    line = make_line

    urls = [ admin_product_lines_path, admin_product_line_path(line), edit_admin_product_line_path(line), new_admin_product_line_content_episode_path(line) ]

    urls.each do |url|
      get url
      assert_redirected_to new_user_session_path
    end

    sign_in_as(@user)
    urls.each do |url|
      get url
      assert_redirected_to root_path
    end

    assert_no_difference [ "ProductLine.count", "ContentEpisode.count", "Product.count" ] do
      post admin_product_lines_path, params: { product_line: { internal_name: "x", customer_name: "x", slug: "x", introduction: "소개" } }
      post admin_product_line_content_episodes_path(line), params: { content_episode: { customer_title: "x", position: 1 } }
      patch admin_product_line_sale_path(line), params: { sale: { total_amount: 1000 } }
    end
  end

  test "full flow: Product -> Episode with revision, takeaway, transitions, preview and delete -- no Bundle and no Season anywhere" do
    sign_in_as(@admin)

    # 1. Product (draft by default, public reach)
    post admin_product_lines_path, params: { product_line: {
      internal_name: "R3 내부명", customer_name: "R3 제품", slug: "r3-line", introduction: "소개"
    } }
    line = ProductLine.last
    assert_redirected_to edit_admin_product_line_path(line)
    assert_equal "draft", line.status
    assert_equal "public", line.visibility

    # 2. Episode created from the product screen belongs to that product automatically
    get new_admin_product_line_content_episode_path(line)
    assert_response :success
    assert_no_match(/content_bundle|product_id|묶음|Season/, response.body)
    post admin_product_line_content_episodes_path(line), params: { content_episode: { customer_title: "첫 편", position: 1, body: "# 첫 편\n\n본문 v1" } }
    episode = ContentEpisode.last
    assert_redirected_to edit_admin_content_episode_path(episode)
    assert_equal line, episode.product_line
    assert_nil episode.bundle_id
    assert_nil episode.product_season_id
    assert_equal "draft", episode.status

    get edit_admin_content_episode_path(episode)
    assert_response :success
    assert_select "a[href=?]", edit_admin_product_line_path(line)
    assert_no_match(/묶음으로/, response.body)

    # 3. revision on body change
    patch admin_content_episode_path(episode), params: { content_episode: { customer_title: "첫 편", position: 1, body: "# 첫 편\n\n본문 v2", lock_version: episode.lock_version } }
    assert_equal 1, episode.reload.content_revisions.count
    assert_equal "# 첫 편\n\n본문 v1", episode.content_revisions.first.body_snapshot

    # 4. takeaway
    post admin_content_episode_content_takeaways_path(episode), params: { content_takeaway: { kind: "체크리스트", body: "- [ ] 확인", position: 1 } }
    assert_equal 1, episode.content_takeaways.count

    # 5. admin previews work at every level while everything is still draft
    get admin_product_line_path(line)
    assert_response :success
    assert_match(/R3 제품/, response.body)
    assert_match(/첫 편/, response.body)
    get admin_content_episode_path(episode)
    assert_response :success
    assert_match(/본문 v2/, response.body)

    # 6. status transitions go through the shared validated path
    patch transition_admin_content_episode_path(episode, status: "in_review")
    assert_equal "in_review", episode.reload.status
    patch transition_admin_content_episode_path(episode, status: "published")
    assert_equal "published", episode.reload.status
    patch transition_admin_content_episode_path(episode, status: "published")
    assert_redirected_to edit_admin_content_episode_path(episode)
    assert_equal "published", episode.reload.status

    # 7. delete returns to the product, cascading revisions/takeaways
    assert_difference [ "ContentEpisode.count", "ContentRevision.count", "ContentTakeaway.count" ], -1 do
      delete admin_content_episode_path(episode)
    end
    assert_redirected_to edit_admin_product_line_path(line)
    follow_redirect!
    assert_match(/아직 편이 없습니다/, response.body)
  end

  test "the new-product screens never send the author to /admin/content_bundles" do
    sign_in_as(@admin)
    line = make_line
    episode = line.content_episodes.create!(position: 1, customer_title: "편")

    [ edit_admin_product_line_path(line), admin_product_line_path(line), new_admin_product_line_content_episode_path(line),
      edit_admin_content_episode_path(episode), admin_content_episode_path(episode) ].each do |url|
      get url
      assert_response :success
      assert_no_match(%r{/admin/content_bundles}, response.body, "#{url} links to the legacy bundle screens")
    end

    # only the list screen carries the clearly-labelled auxiliary legacy link
    get admin_product_lines_path
    assert_match(/기존 DB 콘텐츠 관리/, response.body)
  end

  test "product edits persist, including lifecycle state, visibility and the series relation" do
    sign_in_as(@admin)
    line = make_line

    patch admin_product_line_path(line), params: { product_line: { customer_name: "바뀐 이름", status: "published", visibility: "unlisted",
      series_key: "was-core", series_label: "시즌2", series_position: 2 } }
    line.reload
    assert_equal [ "바뀐 이름", "published", "unlisted", "was-core", "시즌2", 2 ],
      [ line.customer_name, line.status, line.visibility, line.series_key, line.series_label, line.series_position ]

    patch admin_product_line_path(line), params: { product_line: { series_key: "  ", visibility: "secret" } }
    assert_response :unprocessable_entity
    assert_equal "unlisted", line.reload.visibility, "an invalid value saves nothing"
    patch admin_product_line_path(line), params: { product_line: { series_key: "" } }
    assert_nil line.reload.series_key
  end

  test "the product edit screen carries the visibility, series and sale controls, and no Season screens exist" do
    sign_in_as(@admin)
    line = make_line
    get edit_admin_product_line_path(line)
    assert_response :success
    assert_select "select[name='product_line[visibility]']"
    assert_select "input[name='product_line[series_key]']"
    assert_select "input[name='product_line[series_label]']"
    assert_select "input[name='product_line[series_position]']"
    assert_select "input[name='product_line[summary]']"
    assert_select "#sale-settings form[action=?]", admin_product_line_sale_path(line)
    assert_select "#episodes a[href=?]", new_admin_product_line_content_episode_path(line), text: "+ 새 편"
    assert_no_match(/Season/, css_select("main").text)
  end

  # Handoff 0068 -- the customer product list's one-line summary. No length validation
  # (a recommendation only), never auto-filled from the introduction.
  test "the one-line summary saves, is never required, and existing lines start blank" do
    sign_in_as(@admin)
    line = make_line
    assert_nil line.summary, "existing data is never auto-filled from the introduction"

    patch admin_product_line_path(line), params: { product_line: { summary: "요약 문장입니다" } }
    assert_equal "요약 문장입니다", line.reload.summary

    patch admin_product_line_path(line), params: { product_line: { summary: "" } }
    assert_response :redirect, "a blank summary is not a validation error"
    assert_not line.reload.summary.present?

    post admin_product_lines_path, params: { product_line: { internal_name: "새 제품", customer_name: "새 제품", slug: "new-no-summary", introduction: "소개" } }
    assert ProductLine.find_by(slug: "new-no-summary").present?
  end

  test "invalid create/update never partially saves" do
    sign_in_as(@admin)
    line = make_line

    assert_no_difference [ "ProductLine.count" ] do
      post admin_product_lines_path, params: { product_line: { internal_name: "", customer_name: "", slug: line.slug, introduction: "" } }
      assert_response :unprocessable_entity
    end

    post admin_product_line_content_episodes_path(line), params: { content_episode: { customer_title: "첫 편", position: 1 } }
    assert_equal 1, line.content_episodes.count
    assert_no_difference "ContentEpisode.count" do
      post admin_product_line_content_episodes_path(line), params: { content_episode: { customer_title: "같은 순서", position: 1 } }
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
    assert_nil episode.product_line_id

    delete admin_content_episode_path(episode)
    assert_redirected_to edit_admin_content_bundle_path(bundle)
  end
end
