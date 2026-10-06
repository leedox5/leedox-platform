require "test_helper"

# Handoff 0084 R2 (D-010) -- an episode is "series viewing": its body is dark like the series pages, with the display
# serif, .doc-content-dark and a dark comment section. Colors only -- content, the comment flow, view counts and the
# prefetch opt-out are covered, unchanged, by episode_comments_test, episode_comment_moderation_test,
# episode_view_counts_test and product_line_customer_test. The admin preview and the legacy chapters keep their look.
class DarkEpisodeTest < ActionDispatch::IntegrationTest
  BROWSER = { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36" }.freeze
  DARK_HEADER = "header.bg-\\[\\#0e1014\\]\\/90"
  LIGHT_HEADER = "header.bg-white\\/90"

  setup do
    @admin = User.create!(name: "관리자", email: "de-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @user = User.create!(name: "앨리스", email: "de-#{SecureRandom.hex(3)}@example.com", password: "password123")
    @line = ProductLine.create!(internal_name: "어둠", customer_name: "어둠 시리즈", slug: "dark-episode", introduction: "소개", status: "published")
    @ep1 = @line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "머리말\n\n## 소제목\n\n본문", status: "published")
    @ep2 = @line.content_episodes.create!(position: 2, customer_title: "둘째 편", body: "본문 2", status: "published")
    @ep1.content_takeaways.create!(kind: "체크리스트", body: "- 항목", position: 1)
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def episode_path(episode = @ep1) = product_episode_path(@line.slug, episode.display_id)

  test "the episode body is dark, titled after the episode, with the display serif and .doc-content-dark" do
    get episode_path
    assert_response :success
    assert_select "title", text: "첫 편 | LEEDOX"
    assert_select "link[rel='preload'][href*='Pretendard-Bold']", 1
    assert_select "div.bg-\\[\\#0e1014\\] > #{DARK_HEADER}"
    assert_select "main h1.font-display.text-\\[\\#f2efe8\\]", text: "첫 편"
    assert_select "main > .doc-content.doc-content-dark h2", text: "소제목"
    assert_select "main .bg-\\[\\#f0a53c\\]\\/10 .doc-content.doc-content-dark li", text: "항목"
    assert_select "main a.text-\\[\\#a8a39a\\][data-turbo-prefetch='false'][href=?]", episode_path(@ep2)
    html = css_select("main").first.to_html
    %w[bg-white text-gray- bg-gray- text-blue- bg-blue- border-gray- bg-amber-].each { |light| assert_not_includes html, light }
  end

  test "the comment section is dark for a guest: heading, count, sign-in prompt, empty state" do
    get episode_path
    assert_select "#comments.border-white\\/10 h2.text-\\[\\#f2efe8\\]", text: /댓글/
    assert_select "#comments h2 span.text-\\[\\#a8a39a\\]", text: "0"
    assert_select "#comments p.bg-\\[\\#15181e\\] a.text-\\[\\#f0a53c\\]", text: "로그인하고 댓글 쓰기"
    assert_select "#comments p.text-\\[\\#a8a39a\\]", text: "첫 댓글을 남겨 보세요."
  end

  test "comments, replies, the admin badge and the form are dark; a hidden comment is dimmed to 75%" do
    parent = @ep1.episode_comments.create!(user: @user, body: "좋은 편")
    @ep1.episode_comments.create!(user: @admin, body: "감사합니다", parent: parent)
    hidden = @ep1.episode_comments.create!(user: @user, body: "숨길 댓글", hidden_at: Time.current)
    sign_in(@admin)
    get episode_path, headers: BROWSER

    assert_select "#comment-#{parent.id} p.text-\\[\\#c9c4ba\\]", text: "좋은 편"
    assert_select "#comment-#{parent.id} span.text-\\[\\#a8a39a\\]", minimum: 1 # time
    assert_select "#comments div.border-white\\/10 span.bg-\\[\\#f0a53c\\].text-\\[\\#0e1014\\]", text: "운영자"
    assert_select "#comments summary.text-\\[\\#a8a39a\\]", text: "답글"
    assert_select "#comment-#{parent.id} form button.text-\\[\\#a8a39a\\]", text: "숨김"
    assert_select "#comment-#{hidden.id}.opacity-75 span.text-\\[\\#c9c4ba\\]", text: "숨김"
    assert_select "#comments textarea.bg-\\[\\#15181e\\].text-\\[\\#f2efe8\\]", minimum: 1
    assert_select "#comments input[type=submit].bg-\\[\\#f0a53c\\].text-\\[\\#0e1014\\]", minimum: 1
    html = css_select("#comments").first.to_html
    %w[text-gray- bg-gray- text-blue- bg-blue- border-gray- opacity-50].each { |light| assert_not_includes html, light }
  end

  test "a rejected comment re-renders the dark page with the error in the dark palette" do
    sign_in(@user)
    post product_episode_comments_path(@line.slug, @ep1.display_id), params: { episode_comment: { body: "" } }, headers: BROWSER
    assert_response :unprocessable_entity
    assert_select "div.bg-\\[\\#0e1014\\] > #{DARK_HEADER}"
    assert_select "#comments p.text-\\[\\#ff8a80\\][role=alert]"
  end

  test "the admin preview of an episode keeps its light look" do
    sign_in(@admin)
    get admin_content_episode_path(@ep1)
    assert_response :success
    assert_select LIGHT_HEADER, 1
    html = css_select("main").first.to_html
    assert_not_includes html, "doc-content-dark"
    assert_not_includes html, "#0e1014"
    assert_select "main p.uppercase.text-blue-600", text: /Episode/
  end

  test "the legacy chapter templates are untouched by the dark episode" do
    Dir[Rails.root.join("app/views/product_content/*.erb")].each do |file|
      assert_no_match(/doc-content-dark|bg-\[#0e1014\]|font-display/, File.read(file), file)
    end
  end
end
