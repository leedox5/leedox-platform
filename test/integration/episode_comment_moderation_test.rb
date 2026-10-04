require "test_helper"

# Handoff 0074 R2 -- admin hide/unhide (on the episode page and in /admin/comments), what customers and
# admins see of a hidden comment, masked names, and comment actions not counting as episode views.
class EpisodeCommentModerationTest < ActionDispatch::IntegrationTest
  include EpisodeCommentsHelper

  BROWSER = { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36" }.freeze

  setup do
    @admin = User.create!(name: "관리자", email: "mod-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @alice = User.create!(name: "이명호", email: "alice-#{SecureRandom.hex(3)}@example.com", password: "password123")
    @bob = User.create!(name: "Tommy", email: "bob-#{SecureRandom.hex(3)}@example.com", password: "password123")
    @line = ProductLine.create!(internal_name: "숨김", customer_name: "숨김 시리즈", slug: "hide-line", introduction: "소개", status: "published")
    @ep = @line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문 1", status: "published")
  end

  def sign_in(user)
    delete destroy_user_session_path
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def episode_path = product_episode_path(@line.slug, "01")
  def comment!(user, body, parent: nil) = @ep.episode_comments.create!(user: user, body: body, parent: parent)
  def section = css_select("#comments").text
  def views = EpisodeView.sum(:view_count)

  # --- masked names (k) --------------------------------------------------------------

  test "masked_name is the first character plus ** whatever the length, 회원 when blank" do
    assert_equal "이**", masked_name("이명호")
    assert_equal "T**", masked_name("Tommy")
    assert_equal "김**", masked_name("김")
    assert_equal "이**", masked_name("  이명호  ")
    assert_equal "👩‍💻**", masked_name("👩‍💻 개발자")
    assert_equal "회원", masked_name("   ")
    assert_equal "회원", masked_name(nil)
  end

  test "customers, the author included, see only masked names -- never the full name or email, not even in attributes" do
    comment!(@alice, "첫 댓글")
    comment!(@bob, "둘째 댓글")
    sign_in(@alice)
    get episode_path, headers: BROWSER
    assert_includes section, "이**"
    assert_includes section, "T**"
    page = css_select("main").to_html
    [ "이명호", "Tommy", @alice.email, @bob.email ].each { |text| assert_not_includes page, text }
  end

  test "the admin sees masked names on the episode page too, but full names and emails in the admin list" do
    comment!(@alice, "첫 댓글")
    sign_in(@admin)
    get episode_path, headers: BROWSER
    assert_includes section, "이**"
    assert_not_includes css_select("main").to_html, "이명호"

    get admin_episode_comments_path
    assert_response :success
    assert_includes response.body, "이명호"
    assert_includes response.body, @alice.email
  end

  # --- hiding on the episode page (g, h) ---------------------------------------------

  test "an admin hides a comment from the episode page and lands back on it; customers then don't see it" do
    comment = comment!(@alice, "숨길 댓글")
    sign_in(@admin)
    get episode_path, headers: BROWSER
    assert_select "#comment-#{comment.id} form[action=?]", hide_admin_episode_comment_path(comment, from: "episode")

    patch hide_admin_episode_comment_path(comment, from: "episode")
    assert_redirected_to product_episode_path(@line.slug, "01", anchor: "comment-#{comment.id}")
    assert comment.reload.hidden?

    follow_redirect!(headers: BROWSER.dup)
    assert_select "#comment-#{comment.id}.opacity-75" # 0084 R2: dark page, 75% so it reads at >= 4.5:1 (was 50%)
    assert_includes css_select("#comment-#{comment.id}").text, "숨길 댓글"
    assert_select "#comment-#{comment.id} span", text: "숨김"
    assert_select "#comment-#{comment.id} form[action=?]", unhide_admin_episode_comment_path(comment, from: "episode")
    assert_select "#comments h2", text: "댓글 0", message: "the count leaves hidden comments out, for the admin too"

    [ @alice, nil ].each do |viewer|
      viewer ? sign_in(viewer) : delete(destroy_user_session_path)
      get episode_path, headers: BROWSER
      assert_not_includes section, "숨길 댓글", "#{viewer&.name || 'guest'} sees a hidden comment"
      assert_select "#comments h2", text: "댓글 0"
    end
  end

  test "a hidden comment with replies leaves 운영자가 숨긴 댓글입니다 for customers, replies kept" do
    parent = comment!(@alice, "숨겨질 부모")
    comment!(@bob, "남는 답글", parent: parent)
    parent.update!(hidden_at: Time.current)

    sign_in(@bob)
    get episode_path, headers: BROWSER
    assert_includes section, "운영자가 숨긴 댓글입니다"
    assert_includes section, "남는 답글"
    assert_not_includes section, "숨겨질 부모"
    assert_select "#comments h2", text: "댓글 1"
    assert_select "#comments details", 0, "no reply form under a hidden comment"
  end

  test "a hidden comment without replies disappears for customers; a hidden reply too" do
    lonely = comment!(@alice, "외로운 댓글")
    parent = comment!(@alice, "부모")
    reply = comment!(@bob, "숨길 답글", parent: parent)
    [ lonely, reply ].each { |c| c.update!(hidden_at: Time.current) }
    get episode_path, headers: BROWSER
    assert_not_includes section, "외로운 댓글"
    assert_not_includes section, "숨길 답글"
    assert_not_includes section, "운영자가 숨긴 댓글입니다"
    assert_includes section, "부모"
  end

  test "unhide brings it back for everyone" do
    comment = comment!(@alice, "다시 보일 댓글")
    comment.update!(hidden_at: Time.current)
    sign_in(@admin)
    patch unhide_admin_episode_comment_path(comment, from: "episode")
    assert_not comment.reload.hidden?
    delete destroy_user_session_path
    get episode_path, headers: BROWSER
    assert_includes section, "다시 보일 댓글"
  end

  test "non-admins have no hide buttons and can't hide by URL" do
    comment = comment!(@alice, "댓글")
    sign_in(@bob)
    get episode_path, headers: BROWSER
    assert_select "#comments form[action*='/admin/comments']", 0
    patch hide_admin_episode_comment_path(comment)
    assert_redirected_to root_path
    assert_not comment.reload.hidden?

    delete destroy_user_session_path
    patch hide_admin_episode_comment_path(comment)
    assert_redirected_to new_user_session_path
    assert_not comment.reload.hidden?
  end

  test "a hidden comment can't be replied to, and the admin never gets a delete button on others' comments" do
    comment = comment!(@alice, "숨긴 댓글")
    comment.update!(hidden_at: Time.current)
    sign_in(@admin)
    get episode_path, headers: BROWSER
    assert_select "#comment-#{comment.id} form[action=?]", product_episode_comment_path(@line.slug, "01", comment), 0
    assert_no_difference -> { EpisodeComment.count } do
      post product_episode_comments_path(@line.slug, "01"), params: { episode_comment: { body: "답글", parent_id: comment.id } }
    end
  end

  test "the admin can still delete their own comment" do
    mine = comment!(@admin, "운영자 댓글")
    sign_in(@admin)
    delete product_episode_comment_path(@line.slug, "01", mine)
    assert mine.reload.deleted?
  end

  # --- admin list (i, j) ----------------------------------------------------------------

  test "the admin list shows every series' comments newest first with link, author, excerpt, status and hide buttons" do
    other_line = ProductLine.create!(internal_name: "다른", customer_name: "다른 시리즈", slug: "other-line", introduction: "소개", status: "published")
    other_ep = other_line.content_episodes.create!(position: 2, customer_title: "다른 편", body: "본문", status: "published")
    old = travel_to(2.hours.ago) { comment!(@alice, "오래된 댓글") }
    hidden = travel_to(1.hour.ago) { comment!(@bob, "숨긴 댓글").tap { |c| c.update!(hidden_at: Time.current) } }
    deleted = travel_to(30.minutes.ago) { comment!(@alice, "지운 댓글").tap(&:soft_delete!) }
    newest = other_ep.episode_comments.create!(user: @bob, body: "가장 새 댓글 " + ("긴 내용 " * 30))
    gone_user = User.create!(name: "떠난이", email: "gone-#{SecureRandom.hex(3)}@example.com", password: "password123")
    gone = travel_to(3.hours.ago) { comment!(gone_user, "탈퇴자 댓글") }
    gone_user.destroy!

    sign_in(@admin)
    get admin_episode_comments_path
    assert_response :success
    rows = css_select("tbody tr")
    assert_equal [ newest, deleted, hidden, old, gone ].map { |c| "comment-#{c.id}" }, rows.map { |r| r["id"] }
    link = css_select("#comment-#{newest.id} a[href='#{product_episode_path("other-line", "02", anchor: "comment-#{newest.id}")}']").first
    assert_equal [ "다른 시리즈", "02 다른 편" ], link.css("span").map { |n| n.text.strip }, "series and episode on two lines"
    assert_operator css_select("#comment-#{newest.id} td p").first.text.length, :<=, 80
    assert_equal %w[공개 삭제됨 숨김 공개 공개], rows.map { |r| r.at_css("[data-comment-status]").text.strip }
    assert_select "#comment-#{old.id} form[action=?]", hide_admin_episode_comment_path(old)
    assert_select "#comment-#{hidden.id} form[action=?]", unhide_admin_episode_comment_path(hidden)
    assert_select "#comment-#{deleted.id} form", 0
    assert_includes css_select("#comment-#{gone.id}").text, "탈퇴한 사용자"
  end

  # R3 -- a fixed table layout so a long excerpt can't squeeze the other columns or push 상태/관리 off screen.
  test "the admin list uses a fixed layout: set widths for every column but 내용, which truncates" do
    comment!(@alice, "아주 긴 댓글 " * 50)
    sign_in(@admin)
    get admin_episode_comments_path
    assert_select "table.table-fixed.w-full"
    assert_equal [ true, true, true, false, true, true ], css_select("table colgroup col").map { |col| col["class"].to_s.start_with?("w-") }
    assert_select "tbody td p.truncate[title]"
  end

  test "hide/unhide from the list returns to the list" do
    comment = comment!(@alice, "댓글")
    sign_in(@admin)
    patch hide_admin_episode_comment_path(comment)
    assert_redirected_to admin_episode_comments_path(anchor: "comment-#{comment.id}")
    assert comment.reload.hidden?
    patch unhide_admin_episode_comment_path(comment)
    assert_not comment.reload.hidden?
  end

  test "the admin dashboard links to the comment list; non-admins can't open it" do
    sign_in(@admin)
    get admin_dashboard_path
    assert_select "a[href=?]", admin_episode_comments_path, minimum: 1
    sign_in(@alice)
    get admin_episode_comments_path
    assert_redirected_to root_path
  end

  # --- comment actions aren't episode views (l) -------------------------------------------

  test "posting a comment and following the redirect adds no view; the next ordinary visit does" do
    sign_in(@alice)
    get episode_path, headers: BROWSER
    assert_equal 1, views

    post product_episode_comments_path(@line.slug, "01"), params: { episode_comment: { body: "댓글" } }
    follow_redirect!(headers: BROWSER.dup)
    assert_response :success
    assert_equal 1, views, "the redirect back after posting isn't a view"

    get episode_path, headers: BROWSER
    assert_equal 2, views, "the marker doesn't outlive the redirect"
  end

  test "deleting, a rate-limited post, and an admin hide/unhide from the page add no view either" do
    sign_in(@alice)
    mine = comment!(@alice, "내 댓글")
    delete product_episode_comment_path(@line.slug, "01", mine)
    follow_redirect!(headers: BROWSER.dup)
    5.times { |i| comment!(@alice, "도배 #{i}") }
    post product_episode_comments_path(@line.slug, "01"), params: { episode_comment: { body: "여섯 번째" } }
    assert_equal "잠시 후 다시 시도해 주세요.", flash[:alert]
    follow_redirect!(headers: BROWSER.dup)
    assert_equal 0, views

    target = comment!(@bob, "숨길 댓글")
    sign_in(@admin)
    patch hide_admin_episode_comment_path(target, from: "episode")
    follow_redirect!(headers: BROWSER.dup)
    patch unhide_admin_episode_comment_path(target, from: "episode")
    follow_redirect!(headers: BROWSER.dup)
    assert_equal 0, views
  end

  test "the marker only covers the episode it was set for, and only the next request" do
    other = @line.content_episodes.create!(position: 2, customer_title: "둘째 편", body: "본문 2", status: "published")
    sign_in(@alice)
    post product_episode_comments_path(@line.slug, "01"), params: { episode_comment: { body: "댓글" } }
    get product_episode_path(@line.slug, other.display_id), headers: BROWSER # marker for E01 is consumed here
    assert_equal 1, EpisodeView.where(content_episode: other).sum(:view_count), "a different episode still counts"
    get episode_path, headers: BROWSER
    assert_equal 1, EpisodeView.where(content_episode: @ep).sum(:view_count), "the marker is gone after one request"
  end

  test "nothing in the URL can switch view counting off" do
    get episode_path, params: { skip_episode_view: @ep.id }, headers: BROWSER
    get product_episode_path(@line.slug, "01", flash: { skip_episode_view: @ep.id }), headers: BROWSER
    assert_equal 2, views, "both visits counted -- a param named like the marker does nothing"
    assert_equal 2, EpisodeView.sole.view_count
  end
end
