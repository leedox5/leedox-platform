require "test_helper"

# Handoff 0055 follow-up -- the simplest possible "undo an episode" tool:
# permanent delete, no archive/trash/restore, no renumbering of siblings.
class AdminContentEpisodeDeletionTest < ActionDispatch::IntegrationTest
  setup do
    @product = Product.create!(code: "content_lab", name: "Content Lab", active: true)
    @admin = User.create!(name: "관리자", email: "deletion-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @bundle = ContentBundle.create!(product: @product, internal_name: "삭제 테스트 묶음", slug: "deletion-test", status: "published")
    post user_session_path, params: { user: { email: @admin.email, password: "password123" } }
  end

  test "deleting a draft episode removes it and redirects to the bundle edit screen with a completion notice" do
    episode = @bundle.content_episodes.create!(position: 1, customer_title: "삭제될 편", body: "본문", status: "draft")

    delete admin_content_episode_path(episode)
    assert_redirected_to edit_admin_content_bundle_path(@bundle)
    follow_redirect!
    assert_match(/삭제될 편.*삭제했습니다/, response.body)
    assert_not ContentEpisode.exists?(episode.id)
  end

  test "deleting an episode cascades to its takeaways and revisions" do
    episode = @bundle.content_episodes.create!(position: 1, customer_title: "편", body: "본문", status: "draft")
    episode.content_takeaways.create!(kind: "체크리스트", body: "- [ ] 항목", position: 1)
    episode.update!(body: "수정된 본문") # before_update callback snapshots the old body into a revision
    assert_equal 1, episode.content_takeaways.count
    assert_equal 1, episode.content_revisions.count
    takeaway_id = episode.content_takeaways.first.id
    revision_id = episode.content_revisions.first.id

    delete admin_content_episode_path(episode)

    assert_not ContentTakeaway.exists?(takeaway_id)
    assert_not ContentRevision.exists?(revision_id)
  end

  test "deleting one episode does not renumber or otherwise change the remaining episodes' position, body or status" do
    ep1 = @bundle.content_episodes.create!(position: 1, customer_title: "1편", body: "본문1", status: "draft")
    ep2 = @bundle.content_episodes.create!(position: 2, customer_title: "2편", body: "본문2", status: "published")
    ep3 = @bundle.content_episodes.create!(position: 3, customer_title: "3편", body: "본문3", status: "draft")

    delete admin_content_episode_path(ep2)

    ep1.reload
    ep3.reload
    assert_equal [ 1, "본문1", "draft" ], [ ep1.position, ep1.body, ep1.status ]
    assert_equal [ 3, "본문3", "draft" ], [ ep3.position, ep3.body, ep3.status ]
    assert_not ContentEpisode.exists?(ep2.id)
  end

  test "deleting the only remaining episode leaves an empty bundle -- no error, bundle itself untouched" do
    episode = @bundle.content_episodes.create!(position: 1, customer_title: "유일한 편", body: "본문", status: "draft")

    delete admin_content_episode_path(episode)
    assert_redirected_to edit_admin_content_bundle_path(@bundle)

    get edit_admin_content_bundle_path(@bundle)
    assert_response :success
    assert_equal 0, @bundle.reload.content_episodes.count
  end

  test "deleting a published episode makes its existing customer URL 404 immediately" do
    episode = @bundle.content_episodes.create!(position: 1, customer_title: "게시된 편", body: "본문", status: "published")
    get "/content/content_lab/deletion-test/01"
    assert_response :success

    delete admin_content_episode_path(episode)

    get "/content/content_lab/deletion-test/01"
    assert_response :not_found
  end

  test "the edit screen's delete control names the episode, warns it's irreversible and (for published episodes) warns the customer URL disappears -- merely viewing it changes nothing" do
    draft_episode = @bundle.content_episodes.create!(position: 1, customer_title: "초안 편", body: "본문", status: "draft")
    published_episode = @bundle.content_episodes.create!(position: 2, customer_title: "게시 편", body: "본문", status: "published")

    get edit_admin_content_episode_path(draft_episode)
    assert_response :success
    assert_match(/초안 편/, response.body)
    assert_match(/되돌릴 수 없습니다/, response.body)
    assert_no_match(/고객 URL이 즉시 사라집니다/, response.body)

    get edit_admin_content_episode_path(published_episode)
    assert_response :success
    assert_match(/게시 편/, response.body)
    assert_match(/되돌릴 수 없습니다/, response.body)
    assert_match(/고객 URL이 즉시 사라집니다/, response.body)

    # Canceling a data-turbo-confirm dialog never sends a request at all --
    # nothing to assert there beyond "the page render itself is inert."
    assert ContentEpisode.exists?(draft_episode.id)
    assert ContentEpisode.exists?(published_episode.id)
  end
end
