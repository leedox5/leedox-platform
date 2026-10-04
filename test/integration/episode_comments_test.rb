require "test_helper"

# Handoff 0074 R1 -- comments and one level of replies under a customer episode page: same gates as
# the page, signed-in writers, plain escaped text, flood control, author-only soft delete.
class EpisodeCommentsTest < ActionDispatch::IntegrationTest
  BROWSER = { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36" }.freeze

  setup do
    @admin = User.create!(name: "관리자", email: "ec-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @alice = User.create!(name: "앨리스", email: "alice-#{SecureRandom.hex(3)}@example.com", password: "password123")
    @bob = User.create!(name: "밥", email: "bob-#{SecureRandom.hex(3)}@example.com", password: "password123")
    @line = ProductLine.create!(internal_name: "댓글", customer_name: "댓글 시리즈", slug: "comment-line", introduction: "소개", status: "published")
    @ep1 = @line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문 1", status: "published")
    @ep2 = @line.content_episodes.create!(position: 2, customer_title: "둘째 편", body: "본문 2", status: "published")
    @draft = @line.content_episodes.create!(position: 3, customer_title: "예정 편", body: "본문 3", status: "draft")
  end

  def sign_in(user)
    delete destroy_user_session_path
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def episode_path(episode = @ep1) = product_episode_path(@line.slug, episode.display_id)
  def comments_path(episode = @ep1) = product_episode_comments_path(@line.slug, episode.display_id)

  def post_comment(body, parent: nil, episode: @ep1)
    post comments_path(episode), params: { episode_comment: { body: body, parent_id: parent&.id }.compact }
  end

  def comment!(user, body, parent: nil, episode: @ep1, **attrs)
    episode.episode_comments.create!(user: user, body: body, parent: parent, **attrs)
  end

  def thread_texts
    css_select("#comments ol > li").map { |li| li.text.squish }
  end

  # --- seeing ---------------------------------------------------------------

  test "the section sits under the episode with a count and an empty-state line" do
    sign_in(@alice)
    get episode_path, headers: BROWSER
    assert_response :success
    assert_select "#comments h2", text: "댓글 0"
    assert_includes css_select("#comments").text, "첫 댓글을 남겨 보세요."
    assert_select "#comments form textarea[name='episode_comment[body]']"
  end

  test "a guest on an episode open to guests sees the comments and a sign-in link instead of a form" do
    comment!(@alice, "공개 편 댓글")
    get episode_path, headers: BROWSER
    assert_response :success
    assert_includes css_select("#comments").text, "공개 편 댓글"
    assert_select "#comments a[href=?]", new_user_session_path, text: "로그인하고 댓글 쓰기"
    assert_select "#comments form textarea", 0
  end

  test "comments are oldest first, replies indented under their comment oldest first, with name and KST time" do
    first = travel_to(Time.zone.local(2026, 10, 4, 9, 10)) { comment!(@alice, "첫 댓글") }
    travel_to(Time.zone.local(2026, 10, 4, 9, 20)) { comment!(@bob, "둘째 댓글") }
    travel_to(Time.zone.local(2026, 10, 4, 9, 30)) { comment!(@bob, "첫 댓글의 답글 1", parent: first) }
    travel_to(Time.zone.local(2026, 10, 4, 9, 40)) { comment!(@alice, "첫 댓글의 답글 2", parent: first) }

    sign_in(@bob)
    get episode_path, headers: BROWSER
    assert_select "#comments h2", text: "댓글 4"
    texts = thread_texts
    assert_equal 2, texts.size
    assert_match(/앨\*\* 2026\.10\.04 09:10 첫 댓글.*밥\*\* 2026\.10\.04 09:30 .*첫 댓글의 답글 1.*앨\*\* 2026\.10\.04 09:40 첫 댓글의 답글 2/, texts[0])
    assert_match(/밥\*\* 2026\.10\.04 09:20 .*둘째 댓글/, texts[1])
    assert_select "#comment-#{first.replies.first.id}.ml-6"
  end

  # 0074 R2 -- names are masked (first character + "**"); the full name and the email appear nowhere on the page.
  test "names are masked and never the email; an admin reads LEEDOX + 운영자; a deleted account reads 탈퇴한 사용자" do
    comment!(@alice, "일반 회원의 댓글")
    comment!(@admin, "운영자 댓글")
    gone = User.create!(name: "떠난이", email: "gone-#{SecureRandom.hex(3)}@example.com", password: "password123")
    comment!(gone, "떠난 사람의 댓글")
    gone.destroy!

    get episode_path, headers: BROWSER
    section = css_select("#comments").text
    assert_includes section, "LEEDOX"
    assert_includes section, "운영자"
    assert_not_includes section, "관리자" # the admin's own name isn't shown either
    assert_includes section, "탈퇴한 사용자"
    assert_includes section, "떠난 사람의 댓글"
    assert_includes section, "앨**"
    assert_not_includes response.body, "앨리스"
    [ @admin, @alice ].each { |user| assert_not_includes response.body, user.email }
    assert_no_match(/@example\.com/, section)
  end

  test "comments are only visible behind the same gates as the episode (draft 404, gated redirects)" do
    comment!(@alice, "보이면 안 되는 댓글", episode: @draft)
    get episode_path(@draft), headers: BROWSER
    assert_response :not_found
    assert_not_includes response.body, "보이면 안 되는 댓글"

    gate!(@line)
    comment!(@alice, "유료 편 댓글")
    get episode_path, headers: BROWSER
    assert_redirected_to new_user_session_path
    sign_in(@bob)
    get episode_path, headers: BROWSER
    assert_redirected_to product_line_path(@line.slug)
  ensure
    restore_commerce_env
  end

  test "the admin episode preview has no comment section" do
    comment!(@alice, "미리보기에 없어야 할 댓글")
    sign_in(@admin)
    get admin_content_episode_path(@ep1), headers: BROWSER
    assert_response :success
    assert_select "#comments", 0
    assert_not_includes response.body, "미리보기에 없어야 할 댓글"
  end

  # --- writing ---------------------------------------------------------------

  test "a signed-in reader posts a comment and lands back on it" do
    sign_in(@alice)
    assert_difference -> { EpisodeComment.count }, 1 do
      post_comment("  좋은 글이네요\n두 번째 줄  ")
    end
    comment = EpisodeComment.last
    assert_redirected_to product_episode_path(@line.slug, "01", anchor: "comment-#{comment.id}")
    assert_equal [ "좋은 글이네요\n두 번째 줄", @alice, @ep1, nil ], [ comment.body, comment.user, comment.content_episode, comment.parent ]
    follow_redirect!
    assert_equal "좋은 글이네요\n두 번째 줄", css_select("#comment-#{comment.id} p.whitespace-pre-wrap").first.text
  end

  test "HTML and markdown are shown as text, never interpreted; URLs aren't linked" do
    sign_in(@alice)
    post_comment("<script>alert(1)</script> **굵게** <b>b</b> https://example.com")
    follow_redirect!
    body = css_select("#comments p.whitespace-pre-wrap").first
    assert_equal "<script>alert(1)</script> **굵게** <b>b</b> https://example.com", body.text
    assert_empty body.css("script, b, strong, a")
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  test "blank and over-1000 comments aren't saved; the text stays and the reason shows" do
    sign_in(@alice)
    assert_no_difference -> { EpisodeComment.count } do
      post_comment("   \n  ")
      assert_response :unprocessable_entity
      assert_includes css_select("#comments [role=alert]").text, "내용을 입력해 주세요."

      long = "가" * 1001
      post_comment(long)
      assert_response :unprocessable_entity
      assert_includes css_select("#comments [role=alert]").text, "1000자까지 쓸 수 있습니다."
      assert_equal long, css_select("#comments textarea").first.text.strip
    end
    assert_includes response.body, "본문 1", "the episode itself re-renders around the form"

    assert_difference -> { EpisodeComment.count }, 1 do
      post_comment("가" * 1000)
    end
  end

  test "guests can't post or delete, even straight to the URL" do
    comment = comment!(@alice, "앨리스 댓글")
    assert_no_difference -> { EpisodeComment.count } do
      post_comment("게스트 댓글")
    end
    assert_redirected_to new_user_session_path
    delete product_episode_comment_path(@line.slug, "01", comment)
    assert_redirected_to new_user_session_path
    assert_not comment.reload.deleted?
  end

  test "someone who can't open a gated episode can't post to it by URL; a licensed reader can" do
    gate!(@line)
    sign_in(@bob)
    assert_no_difference -> { EpisodeComment.count } do
      post_comment("무라이선스 댓글")
    end
    assert_redirected_to product_line_path(@line.slug)

    license!(@bob, @line)
    assert_difference -> { EpisodeComment.count }, 1 do
      post_comment("구매자 댓글")
    end
  ensure
    restore_commerce_env
  end

  test "no posting to a draft episode" do
    sign_in(@alice)
    assert_no_difference -> { EpisodeComment.count } do
      post_comment("draft 댓글", episode: @draft)
    end
    assert_response :not_found
  end

  test "flood control: at most 5 comments/replies a minute per user" do
    sign_in(@alice)
    parent = comment!(@bob, "부모")
    4.times { |i| post_comment("댓글 #{i}") }
    post_comment("답글도 센다", parent: parent)
    assert_equal 5, @alice.episode_comments.count

    assert_no_difference -> { EpisodeComment.count } do
      post_comment("여섯 번째")
    end
    assert_redirected_to product_episode_path(@line.slug, "01", anchor: "comments")
    assert_equal "잠시 후 다시 시도해 주세요.", flash[:alert]

    sign_in(@bob)
    assert_difference -> { EpisodeComment.count }, 1, "another user isn't limited" do
      post_comment("밥의 댓글")
    end

    travel 61.seconds do
      sign_in(@alice)
      assert_difference -> { EpisodeComment.count }, 1 do
        post_comment("1분 뒤")
      end
    end
  end

  test "an admin can comment, with the 운영자 badge" do
    sign_in(@admin)
    post_comment("운영자입니다")
    follow_redirect!
    comment = css_select("#comment-#{EpisodeComment.last.id}").first
    assert_equal [ "LEEDOX", "운영자" ], comment.css("span.font-bold, span.rounded-full").map { |n| n.text.strip }.first(2)
  end

  test "posting a comment doesn't add an episode view (0073 counts only the episode page GET)" do
    sign_in(@alice)
    assert_no_difference -> { EpisodeView.count } do
      post_comment("조회수와 무관")
      post_comment("") # a rejected one re-renders the page -- still not a view
      delete product_episode_comment_path(@line.slug, "01", EpisodeComment.last)
    end
  end

  # --- replies -----------------------------------------------------------------

  test "a reply goes under its comment; replies have no reply form; a reply to a reply is refused by the server" do
    parent = comment!(@bob, "부모 댓글")
    sign_in(@alice)
    post_comment("답글입니다", parent: parent)
    reply = EpisodeComment.last
    assert_equal parent, reply.parent

    get episode_path, headers: BROWSER
    assert_select "#comments details form input[name='episode_comment[parent_id]'][value='#{parent.id}']"
    assert_select "#comments details form input[name='episode_comment[parent_id]'][value='#{reply.id}']", 0

    assert_no_difference -> { EpisodeComment.count } do
      post_comment("답글의 답글", parent: reply)
      assert_response :unprocessable_entity
    end
    assert_includes css_select("#comments [role=alert]").text, "답글에는 답글을 달 수 없습니다."
    assert_equal "답글의 답글", css_select("#comments form textarea").first.text.strip
  end

  test "a reply to another episode's comment, or to a deleted one, is refused" do
    other = comment!(@bob, "다른 편 댓글", episode: @ep2)
    gone = comment!(@bob, "지워진 댓글", deleted_at: Time.current)
    sign_in(@alice)
    assert_no_difference -> { EpisodeComment.count } do
      post_comment("엉뚱한 답글", parent: other)
      assert_response :unprocessable_entity
      post_comment("지워진 곳에 답글", parent: gone)
      assert_response :unprocessable_entity
    end
  end

  test "a rejected reply reopens its own reply form with the text and reason" do
    parent = comment!(@bob, "부모 댓글")
    sign_in(@alice)
    post_comment("", parent: parent)
    assert_response :unprocessable_entity
    details = css_select("#comments details[open]")
    assert_equal 1, details.size
    assert_includes details.first.text, "내용을 입력해 주세요."
  end

  # --- deleting ------------------------------------------------------------------

  test "authors delete their own; others see no button and are refused" do
    mine = comment!(@alice, "앨리스 댓글")
    theirs = comment!(@bob, "밥 댓글")
    sign_in(@alice)
    get episode_path, headers: BROWSER
    assert_select "#comment-#{mine.id} form[action=?]", product_episode_comment_path(@line.slug, "01", mine)
    assert_select "#comment-#{mine.id} button[data-turbo-confirm]"
    assert_select "#comment-#{theirs.id} form", 0

    delete product_episode_comment_path(@line.slug, "01", theirs)
    assert_response :not_found
    assert_not theirs.reload.deleted?

    delete product_episode_comment_path(@line.slug, "01", mine)
    assert_redirected_to product_episode_path(@line.slug, "01", anchor: "comments")
    assert mine.reload.deleted?, "soft-deleted, kept for the admin list"
    follow_redirect!
    assert_not_includes css_select("#comments").text, "앨리스 댓글"
    assert_select "#comments h2", text: "댓글 1"
  end

  test "a deleted comment with replies stays as a placeholder; without replies it disappears" do
    with_replies = comment!(@alice, "답글 달린 댓글")
    comment!(@bob, "남는 답글", parent: with_replies)
    lonely = comment!(@alice, "외로운 댓글")
    sign_in(@alice)
    delete product_episode_comment_path(@line.slug, "01", with_replies)
    delete product_episode_comment_path(@line.slug, "01", lonely)
    get episode_path, headers: BROWSER

    section = css_select("#comments").text
    assert_includes section, "삭제된 댓글입니다"
    assert_includes section, "남는 답글"
    assert_not_includes section, "답글 달린 댓글"
    assert_not_includes section, "외로운 댓글"
    assert_select "#comments h2", text: "댓글 1" # only the reply counts
    assert_select "#comments details", 0, "no reply form under a placeholder"
  end

  test "once its last reply is deleted, a deleted comment's placeholder goes too" do
    parent = comment!(@alice, "부모")
    reply = comment!(@bob, "마지막 답글", parent: parent)
    parent.soft_delete!
    sign_in(@bob)
    delete product_episode_comment_path(@line.slug, "01", reply)
    get episode_path, headers: BROWSER
    assert_not_includes css_select("#comments").text, "삭제된 댓글입니다"
    assert_includes css_select("#comments").text, "첫 댓글을 남겨 보세요."
  end

  # --- data ----------------------------------------------------------------------

  test "deleting an episode deletes its comments" do
    parent = comment!(@alice, "부모", episode: @ep2)
    comment!(@bob, "답글", parent: parent, episode: @ep2)
    assert_difference -> { EpisodeComment.count }, -2 do
      @ep2.destroy!
    end
  end

  test "the page still renders, without the section, when comments can't be loaded" do
    ContentEpisode.class_eval do
      alias_method :__episode_comments, :episode_comments
      define_method(:episode_comments) { raise ActiveRecord::StatementInvalid, "no such table: episode_comments" }
    end
    get episode_path, headers: BROWSER
    assert_response :success
    assert_includes response.body, "본문 1"
    assert_select "#comments", 0
  ensure
    ContentEpisode.class_eval do
      alias_method :episode_comments, :__episode_comments
      remove_method :__episode_comments
    end
  end

  test "the comment thread loads in a fixed number of queries, however many comments" do
    5.times { |i| comment!(i.even? ? @alice : @bob, "댓글 #{i}") }
    parent = EpisodeComment.first
    3.times { |i| comment!(@bob, "답글 #{i}", parent: parent) }
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql] =~ /episode_comments|FROM "users"/ && payload[:name] != "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get episode_path, headers: BROWSER
    end
    comment_queries = queries.grep(/episode_comments/)
    assert_equal 1, comment_queries.size, comment_queries.inspect
    assert_operator queries.grep(/FROM "users"/).size, :<=, 2, queries.inspect
  end

  private

  def gate!(line)
    Commerce::CatalogBootstrap.call!
    @previous_commerce = ENV["LEEDOX_COMMERCE_ENABLED"]
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    Commerce::ProductLineSales.set_price!(product_line: line, total_amount: 10_000, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: line, actor: @admin)
    line.reload
  end

  def license!(user, line)
    order = Commerce::OrderCreator.call!(user: user, product_code: line.product.code, offer_code: line.lifetime_offer.code, requested_start_on: nil, provider: "manual")
    Commerce::ConfirmManualPayment.call!(order: order, actor: @admin)
  end

  def restore_commerce_env
    return unless defined?(@previous_commerce)

    @previous_commerce.nil? ? ENV.delete("LEEDOX_COMMERCE_ENABLED") : ENV["LEEDOX_COMMERCE_ENABLED"] = @previous_commerce
  end
end
