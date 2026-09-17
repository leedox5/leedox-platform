require "test_helper"

# Handoff 0054 R2 -- P0 items the operator-feedback round asked for on top of
# 0053: validated status transitions, admin-preview navigation across draft
# siblings, an admin-only internal_ref/note field, and (P1) checklist
# markdown rendering as a real (disabled) checkbox.
class AdminContentEpisodeLifecycleAndPreviewTest < ActionDispatch::IntegrationTest
  setup do
    @product = Product.create!(code: "content_lab", name: "Content Lab", active: true)
    @admin = User.create!(name: "관리자", email: "lifecycle-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @bundle = ContentBundle.create!(product: @product, internal_name: "라이프사이클 테스트", slug: "lifecycle-test", status: "published")
    @episode = @bundle.content_episodes.create!(customer_title: "편 A", position: 1, body: "- [ ] 할 일\n- [x] 완료한 일\n- 일반 항목", status: "draft")
    post user_session_path, params: { user: { email: @admin.email, password: "password123" } }
  end

  test "every distinct status pair is a valid transition, self-transition is rejected with a reason" do
    %w[draft in_review published unpublished].each do |target|
      next if target == @episode.reload.status

      patch transition_admin_content_episode_path(@episode, status: target)
      assert_redirected_to edit_admin_content_episode_path(@episode)
      assert_equal target, @episode.reload.status
    end

    current = @episode.reload.status
    patch transition_admin_content_episode_path(@episode, status: current)
    assert_redirected_to edit_admin_content_episode_path(@episode)
    follow_redirect!
    assert_match(/이미 #{current} 상태입니다/, response.body)
    assert_equal current, @episode.reload.status # unchanged
  end

  test "an unknown status value is rejected rather than written to the record" do
    patch transition_admin_content_episode_path(@episode, status: "archived_forever")
    assert_redirected_to edit_admin_content_episode_path(@episode)
    follow_redirect!
    assert_match(/알 수 없는 상태입니다/, response.body)
    assert_equal "draft", @episode.reload.status
  end

  test "publish/unpublish routes still work and go through the same validated transition" do
    patch publish_admin_content_episode_path(@episode)
    assert_equal "published", @episode.reload.status
    assert_not_nil @episode.published_at

    patch unpublish_admin_content_episode_path(@episode)
    assert_equal "unpublished", @episode.reload.status
  end

  test "internal_ref is settable via the edit form and never rendered on customer or admin preview screens" do
    patch admin_content_episode_path(@episode), params: {
      content_episode: { internal_ref: "출처: docs/12_email.md -- 관리자 전용 메모, 절대 고객에게 보이면 안 됨", lock_version: @episode.lock_version }
    }
    @episode.reload
    assert_match(/관리자 전용 메모/, @episode.internal_ref)

    get edit_admin_content_episode_path(@episode)
    assert_match(/관리자 전용 메모/, response.body) # the edit form itself should show it back

    get admin_content_episode_path(@episode)
    assert_no_match(/관리자 전용 메모/, response.body) # preview must not leak it

    @episode.update!(status: "published")
    delete destroy_user_session_path
    get "/content/content_lab/lifecycle-test/01"
    assert_no_match(/관리자 전용 메모/, response.body)
  end

  test "admin preview navigates prev/next across draft siblings, unlike the customer path which excludes drafts entirely" do
    second = @bundle.content_episodes.create!(customer_title: "편 B", position: 2, body: "본문 B", status: "draft")

    get admin_content_episode_path(@episode)
    assert_response :success
    assert_select "a[href=?]", admin_content_episode_path(second), text: /편 B/

    get admin_content_episode_path(second)
    assert_response :success
    assert_select "a[href=?]", admin_content_episode_path(@episode), text: /편 A/
  end

  test "a markdown checklist renders as a disabled checkbox, not literal brackets, in both admin preview and the customer screen" do
    get admin_content_episode_path(@episode)
    assert_select "input[type=checkbox][disabled]", count: 2
    assert_select "input[type=checkbox][checked]", count: 1
    assert_no_match(/\[ \]|\[x\]/, response.body)

    @episode.update!(status: "published")
    get "/content/content_lab/lifecycle-test/01"
    assert_response :success
    assert_select "input[type=checkbox][disabled]", count: 2
    assert_select "input[type=checkbox][checked]", count: 1
  end

  test "only the checklist-converted <li> loses its bullet -- a plain bullet item in the same list keeps its default marker" do
    get admin_content_episode_path(@episode)
    doc = Nokogiri::HTML(response.body)
    items = doc.css(".doc-content li")
    checklist_items = items.select { |li| li.at_css("input[type=checkbox]") }
    plain_items = items.reject { |li| li.at_css("input[type=checkbox]") }

    assert_equal 2, checklist_items.size
    assert_equal 1, plain_items.size
    checklist_items.each { |li| assert_match(/list-style-type\s*:\s*none/, li["style"].to_s) }
    plain_items.each { |li| assert_nil li["style"] }
  end
end
