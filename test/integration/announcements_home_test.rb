require "test_helper"

# Handoff 0077 R2 -- the home's one-line pinned notice, the service desk's links to the notice/comment desks.
class AnnouncementsHomeTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(name: "관리자", email: "ah-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
  end

  def line = css_select("[data-home-notice]").first

  test "a published + pinned notice shows as one line under the header, above the hero, linking to it" do
    featured = ProductLine.create!(internal_name: "대표", customer_name: "대표 시리즈", slug: "home-featured", introduction: "소개", status: "published", featured: true)
    featured.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문", status: "published")
    pinned = Announcement.create!(title: "약관 개정 안내", body: "본문", published: true, pinned: true)

    get root_path
    assert_response :success
    assert line, "the notice line is rendered"
    assert_equal announcement_path(pinned), line["href"]
    assert_equal "공지 · 약관 개정 안내 →", line.text.squish
    html = response.body
    assert_operator html.index("data-home-notice"), :>, html.index("</header>"), "below the header"
    assert_operator html.index("data-home-notice"), :<, html.index("featured-series-title"), "above the hero"
  end

  test "no line at all without a published + pinned notice (unpublished pinned, or published unpinned)" do
    get root_path
    assert_nil line

    Announcement.create!(title: "게시만", body: "본문", published: true)
    Announcement.create!(title: "고정만", body: "본문", published: false, pinned: true)
    get root_path
    assert_nil line
    assert_not_includes css_select("main").text + css_select("body > div > div").text, "고정만"
  end

  test "the line is the same for guests, members and admins" do
    Announcement.create!(title: "모두에게", body: "본문", published: true, pinned: true)
    member = User.create!(name: "회원", email: "ah-user-#{SecureRandom.hex(3)}@example.com", password: "password123")
    lines = [ nil, member, @admin ].map do |viewer|
      delete destroy_user_session_path
      post user_session_path, params: { user: { email: viewer.email, password: "password123" } } if viewer
      get root_path
      line.to_html
    end
    assert_equal 1, lines.uniq.size
  end

  test "a long title stays on one line (truncated, full text in the tooltip)" do
    title = "아주 긴 공지 제목 " * 8
    Announcement.create!(title: title.strip.first(100), body: "본문", published: true, pinned: true)
    get root_path
    span = line.css("span.truncate").first
    assert span, "the title span truncates"
    assert_equal title.strip.first(100), span["title"]
  end

  test "the home looks the notice up in a single query and never touches Rails.cache" do
    Announcement.create!(title: "고정", body: "본문", published: true, pinned: true)
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?("announcements") && payload[:name] != "SCHEMA" }
    cache_calls = []
    cache_callback = ->(name, *) { cache_calls << name }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      ActiveSupport::Notifications.subscribed(cache_callback, /cache_(read|write|fetch_hit|generate)\.active_support/) do
        get root_path
      end
    end
    assert_equal 1, queries.size, queries.inspect
    assert_empty cache_calls
  end

  # home_pick is defined on Announcement itself, so the original is kept and put back (removing the stub alone would
  # delete the real method too and break every later test in the process).
  test "the home still renders, without the line, when notices can't be loaded" do
    original = Announcement.method(:home_pick)
    Announcement.define_singleton_method(:home_pick) { raise ActiveRecord::StatementInvalid, "no such table: announcements" }
    get root_path
    assert_response :success
    assert_nil line
  ensure
    Announcement.define_singleton_method(:home_pick, original)
  end

  test "only the home shows the line" do
    Announcement.create!(title: "홈 전용", body: "본문", published: true, pinned: true)
    [ products_path, pricing_path, announcements_path ].each do |path|
      get path
      assert_nil line, "#{path} shows the home notice line"
    end
  end

  test "the service desk links to 공지 관리 and 댓글 관리, with a one-line explanation" do
    post user_session_path, params: { user: { email: @admin.email, password: "password123" } }
    get service_desk_path
    assert_response :success
    nav = css_select("nav[aria-label='운영 바로가기']").first
    assert nav
    assert_equal [ admin_announcements_path, admin_episode_comments_path ], nav.css("a").map { |a| a["href"] }
    assert_includes nav.text, "회원에게 알리는 글은 공지 관리, 편에 달린 댓글은 댓글 관리에서 봅니다."
    assert_includes response.body, "팀과 AI 에이전트가 웹에서 직접 발행/기록하는 운영 티켓입니다."
  end
end
