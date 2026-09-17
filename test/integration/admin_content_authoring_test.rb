require "test_helper"

# Handoff 0053 R3 -- full authoring -> publish -> customer screen -> unpublish
# flow for DB-backed content, plus the safety nets R2 was missing: revision
# snapshots, optimistic locking, and deactivation/registry rollback.
class AdminContentAuthoringTest < ActionDispatch::IntegrationTest
  setup do
    @product = Product.create!(code: "content_lab", name: "Content Lab", active: true)
    @admin = User.create!(name: "관리자", email: "content-lab-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @user = User.create!(name: "일반유저", email: "content-lab-user-#{SecureRandom.hex(3)}@example.com", password: "password123")
  end

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  test "non-admins and guests cannot reach any admin content authoring URL" do
    bundle = ContentBundle.create!(product: @product, internal_name: "차단 테스트")

    get admin_content_bundles_path
    assert_redirected_to new_user_session_path

    sign_in_as(@user)
    get admin_content_bundles_path
    assert_redirected_to root_path
    get edit_admin_content_bundle_path(bundle)
    assert_redirected_to root_path
  end

  test "the full author -> draft preview -> publish -> customer screen -> revision -> unpublish flow" do
    sign_in_as(@admin)

    # 1. create bundle
    post admin_content_bundles_path, params: { content_bundle: { internal_name: "R3 검증 묶음", product_id: @product.id, status: "draft" } }
    bundle = ContentBundle.last
    assert_redirected_to edit_admin_content_bundle_path(bundle)

    # 2. create episode (draft by default)
    post admin_content_bundle_content_episodes_path(bundle), params: {
      content_episode: { customer_title: "R3 편", position: 1, body: "# R3 편\n\n초안 본문입니다." }
    }
    episode = ContentEpisode.last
    assert_equal "draft", episode.status

    # 3. add a takeaway
    post admin_content_episode_content_takeaways_path(episode), params: {
      content_takeaway: { kind: "체크리스트", body: "- [ ] 확인", position: 1 }
    }
    assert_equal 1, episode.content_takeaways.count

    # 4. admin draft preview works while still draft
    get admin_content_episode_path(episode)
    assert_response :success
    assert_match(/초안 본문입니다/, response.body)
    assert_match(/체크리스트/, response.body)

    # 5. draft is invisible on the customer path
    get "/content/content_lab/01"
    assert_response :not_found

    # 6. publish
    patch publish_admin_content_episode_path(episode)
    episode.reload
    assert episode.published?
    assert_not_nil episode.published_at

    delete destroy_user_session_path

    # 7. customer (no admin session) sees title, body and takeaway
    get "/content/content_lab/01"
    assert_redirected_to new_user_session_path # not licensed yet

    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    end_date = today + 1.month
    License.create!(
      user: @user, product: @product, source: "paid", status: "active",
      starts_on: today, last_usable_on: end_date - 1.day,
      access_ends_at: Commerce::PeriodCalculator::KST.local(end_date.year, end_date.month, end_date.day)
    )
    sign_in_as(@user)

    get "/content/content_lab/01"
    assert_response :success
    assert_match(/초안 본문입니다/, response.body)
    assert_match(/체크리스트/, response.body)
    assert_match(/확인/, response.body)

    delete destroy_user_session_path
    sign_in_as(@admin)

    # 8. editing the body creates a revision snapshot of the old body.
    # Capture lock_version as it stood before this edit -- that's the value
    # a second, concurrent editor's form would still be holding afterward.
    lock_version_before_edit = episode.lock_version
    assert_difference -> { episode.content_revisions.count }, 1 do
      patch admin_content_episode_path(episode), params: {
        content_episode: { body: "# R3 편\n\n수정된 본문입니다.", lock_version: lock_version_before_edit }
      }
    end
    episode.reload
    assert_equal "# R3 편\n\n초안 본문입니다.", episode.content_revisions.recent_first.first.body_snapshot
    assert_match(/수정된 본문입니다/, episode.body)

    # 9. a second editor submitting with that now-stale lock_version is
    # rejected (409), not silently overwritten.
    patch admin_content_episode_path(episode), params: {
      content_episode: { body: "# R3 편\n\n동시수정.", lock_version: lock_version_before_edit }
    }
    assert_response :conflict
    episode.reload
    assert_no_match(/동시수정/, episode.body)

    # 10. unpublish hides it from the customer again
    patch unpublish_admin_content_episode_path(episode)
    delete destroy_user_session_path
    sign_in_as(@user)

    get "/content/content_lab/01"
    assert_response :not_found
  end

  test "an inactive Product blocks the customer index and direct chapter URL, but not the admin authoring UI" do
    bundle = ContentBundle.create!(product: @product, internal_name: "비활성 테스트")
    episode = bundle.content_episodes.create!(customer_title: "비활성 편", position: 1, body: "본문", status: "published")

    get "/content/content_lab"
    assert_response :success

    @product.update!(active: false)

    get "/content/content_lab"
    assert_response :not_found

    get "/content/content_lab/01"
    assert_response :not_found

    sign_in_as(@admin)
    get admin_content_episode_path(episode)
    assert_response :success, "admin preview must stay reachable even while the Product is inactive"
  end

  test "removing content_lab from ProductContent.registry falls back safely (404, not 500) and leaves other products untouched" do
    bundle = ContentBundle.create!(product: @product, internal_name: "레지스트리 제거 테스트")
    bundle.content_episodes.create!(customer_title: "편", position: 1, body: "본문", status: "published")

    original_registry = ProductContent.registry
    ProductContent.define_singleton_method(:registry) { {} }
    begin
      get "/content/content_lab"
      assert_response :success # FilesystemSource fallback with no hq/content_lab folder: empty list, not an error
      assert_no_match(/편/, response.body)

      get "/content/content_lab/01"
      assert_response :not_found
    ensure
      ProductContent.define_singleton_method(:registry) { original_registry }
    end

    # Existing filesystem-backed products are unaffected by content_lab's registry entry existing or not.
    get "/docs"
    assert_response :success
    get "/claudox/read"
    assert_response :success
  end
end
