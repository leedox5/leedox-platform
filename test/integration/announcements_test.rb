require "test_helper"

# Handoff 0077 R1 -- notices (공지): a public list/page for everyone, admin writing, one pinned at most,
# Markdown through ContentMarkdown, and a footer link.
class AnnouncementsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(name: "관리자", email: "an-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @user = User.create!(name: "회원", email: "an-user-#{SecureRandom.hex(3)}@example.com", password: "password123")
  end

  def sign_in(user)
    delete destroy_user_session_path
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def notice!(title, published: true, pinned: false, body: "본문", at: nil)
    record = Announcement.create!(title: title, body: body, published: published, pinned: pinned)
    record.update_columns(published_at: at) if at
    record
  end

  # --- model -------------------------------------------------------------------

  test "published_at is stamped on first publish and kept after unpublish/republish" do
    record = Announcement.create!(title: "초안", body: "본문")
    assert_nil record.published_at
    travel_to(Time.zone.local(2026, 10, 4, 10, 0)) { record.update!(published: true) }
    first = record.reload.published_at
    assert_equal Time.zone.local(2026, 10, 4, 10, 0), first
    travel_to(Time.zone.local(2026, 10, 5, 9, 0)) do
      record.update!(published: false)
      record.update!(published: true)
    end
    assert_equal first, record.reload.published_at
  end

  test "title is 1-100 characters and body is required" do
    assert_not Announcement.new(title: "  ", body: "본문").valid?
    assert_not Announcement.new(title: "가" * 101, body: "본문").valid?
    assert Announcement.new(title: "가" * 100, body: "본문").valid?
    assert_not Announcement.new(title: "제목", body: "").valid?
  end

  test "pinning one unpins the previous one in the same save; the database refuses two" do
    first = notice!("첫 고정", pinned: true)
    second = notice!("새 고정", pinned: true)
    assert_not first.reload.pinned?
    assert second.reload.pinned?
    assert_raises(ActiveRecord::RecordNotUnique) { first.update_columns(pinned: true) }
  end

  test "an unpublished notice can be pinned, but isn't the home pick" do
    notice!("미게시 고정", published: false, pinned: true)
    assert_nil Announcement.home_pick
    live = notice!("게시 고정", pinned: true)
    assert_equal live, Announcement.home_pick
  end

  # --- public pages ---------------------------------------------------------------

  test "the list shows published notices, the pinned one first then newest, with dates and 고정; drafts are left out" do
    old = notice!("오래된 공지", at: Time.zone.local(2026, 9, 1, 9))
    new_one = notice!("새 공지", at: Time.zone.local(2026, 10, 3, 9))
    pinned = notice!("고정 공지", pinned: true, at: Time.zone.local(2026, 8, 1, 9))
    notice!("미게시 공지", published: false)

    get announcements_path
    assert_response :success
    assert_select "title", text: "공지 | LEEDOX"
    rows = css_select("main li a")
    assert_equal [ pinned, new_one, old ].map { |n| announcement_path(n) }, rows.map { |a| a["href"] }
    assert_equal [ "고정 고정 공지 2026.08.01", "새 공지 2026.10.03", "오래된 공지 2026.09.01" ], rows.map { |a| a.text.squish }
    assert_not_includes response.body, "미게시 공지"
  end

  test "an empty list says so" do
    get announcements_path
    assert_includes css_select("main").text, "등록된 공지가 없습니다."
  end

  test "a notice page shows title, date, rendered body and a way back; the title is in <title>" do
    record = notice!("약관 개정 안내", body: "**굵게** 와 [약관](/terms)\n\n- 하나\n- 둘", at: Time.zone.local(2026, 10, 4, 10))
    get announcement_path(record)
    assert_response :success
    assert_select "title", text: "약관 개정 안내 | LEEDOX"
    assert_select "main h1", text: "약관 개정 안내"
    assert_includes css_select("main").text, "2026.10.04"
    assert_select "main .doc-content strong", text: "굵게"
    assert_select "main .doc-content a[href='/terms']", text: "약관"
    assert_select "main .doc-content ul li", 2
    assert_select "main a[href=?]", announcements_path
  end

  test "raw HTML and images in the body never render" do
    record = notice!("보안", body: "<script>alert(1)</script> <img src=x onerror=alert(1)> ![x](https://evil.example/x.png) [js](javascript:alert(1))")
    get announcement_path(record)
    content = css_select("main .doc-content").first
    assert_empty content.css("script, img, iframe")
    assert content.css("a").none? { |a| a["href"].to_s.start_with?("javascript") }
    assert_includes response.body, "&lt;script&gt;"
  end

  test "an unpublished notice is a 404 for guests, members and admins alike" do
    draft = notice!("미게시", published: false)
    [ nil, @user, @admin ].each do |viewer|
      viewer ? sign_in(viewer) : delete(destroy_user_session_path)
      get announcement_path(draft)
      assert_response :not_found, "#{viewer&.name || 'guest'} opened an unpublished notice"
    end
    get announcement_path(id: 999_999)
    assert_response :not_found
  end

  test "guests, members and admins see the same list and page (no login branch)" do
    record = notice!("모두에게", body: "같은 본문")
    bodies = [ nil, @user, @admin ].map do |viewer|
      viewer ? sign_in(viewer) : delete(destroy_user_session_path)
      get announcements_path
      list = css_select("main ul").to_html
      get announcement_path(record)
      [ list, css_select("main article").to_html ]
    end
    assert_equal 1, bodies.uniq.size
  end

  # --- footer -----------------------------------------------------------------------

  test "the footer has 공지 right before 이용 약관, legal links unchanged" do
    get root_path
    links = css_select("footer a").map { |a| [ a.text.strip, a["href"] ] }
    assert_equal [ "LEEDOX 소개", about_path ], links[0] # 0098
    assert_equal [ "공지", announcements_path ], links[1]
    assert_equal [ "이용 약관", terms_path ], links[2]
    assert_equal [ "개인정보 처리 방침", privacy_path ], links[3]
    assert_equal "사업자정보확인", links[4][0]
    get announcements_path
    assert_select "footer a[href=?]", announcements_path, text: "공지"
  end

  # --- admin ---------------------------------------------------------------------------

  test "only admins reach the admin notice screens" do
    get admin_announcements_path
    assert_redirected_to new_user_session_path
    sign_in(@user)
    get admin_announcements_path
    assert_redirected_to root_path
    assert_no_difference -> { Announcement.count } do
      post admin_announcements_path, params: { announcement: { title: "회원", body: "x" } }
    end
  end

  test "an admin creates a notice, and what was saved reads back the same" do
    sign_in(@admin)
    assert_difference -> { Announcement.count }, 1 do
      post admin_announcements_path, params: { announcement: { title: "  새 공지  ", body: "본문\n둘째 줄", published: "1", pinned: "1" } }
    end
    record = Announcement.last
    assert_redirected_to edit_admin_announcement_path(record)
    follow_redirect!
    assert_select "input[name='announcement[title]'][value=?]", "새 공지"
    assert_equal "본문\n둘째 줄", css_select("textarea[name='announcement[body]']").first.text.strip
    assert_select "input[type=checkbox][name='announcement[published]'][checked]"
    assert_select "input[type=checkbox][name='announcement[pinned]'][checked]"
    assert record.reload.published_at.present?
  end

  test "an admin edits, unpublishes and deletes" do
    record = notice!("수정 전")
    sign_in(@admin)
    patch admin_announcement_path(record), params: { announcement: { title: "수정 후", published: "0" } }
    assert_redirected_to edit_admin_announcement_path(record)
    assert_equal [ "수정 후", false ], [ record.reload.title, record.published? ]
    get announcement_path(record)
    assert_response :not_found

    get edit_admin_announcement_path(record)
    assert_select "button[data-turbo-confirm]", text: "공지 삭제"
    assert_difference -> { Announcement.count }, -1 do
      delete admin_announcement_path(record)
    end
    assert_redirected_to admin_announcements_path
  end

  test "invalid input re-renders the form with Korean reasons and keeps the text" do
    sign_in(@admin)
    assert_no_difference -> { Announcement.count } do
      post admin_announcements_path, params: { announcement: { title: "", body: "남는 본문" } }
    end
    assert_response :unprocessable_entity
    assert_includes css_select("[role=alert]").text, "제목을 입력해 주세요."
    assert_equal "남는 본문", css_select("textarea[name='announcement[body]']").first.text.strip
  end

  test "pinning from the admin form unpins the previous one" do
    first = notice!("첫 고정", pinned: true)
    second = notice!("두 번째")
    sign_in(@admin)
    patch admin_announcement_path(second), params: { announcement: { pinned: "1" } }
    assert second.reload.pinned?
    assert_not first.reload.pinned?
  end

  test "the admin list shows status, pin, dates and links; preview shows an unpublished notice with a banner" do
    draft = notice!("미게시 초안", published: false)
    live = notice!("게시 중", pinned: true, at: Time.zone.local(2026, 10, 4, 10))
    sign_in(@admin)
    get admin_announcements_path
    assert_response :success
    assert_equal "게시", css_select("#announcement-#{live.id} [data-status]").text.strip
    assert_equal "고정", css_select("#announcement-#{live.id} [data-pinned]").text.strip
    assert_includes css_select("#announcement-#{live.id}").text, "2026.10.04"
    assert_equal "미게시", css_select("#announcement-#{draft.id} [data-status]").text.strip
    assert_select "#announcement-#{draft.id} a[href=?]", preview_admin_announcement_path(draft)

    get preview_admin_announcement_path(draft)
    assert_response :success
    assert_includes css_select("main").text, "미게시 — 고객에게 보이지 않습니다."
    assert_select "main h1", text: "미게시 초안"
    assert_select "main a[href=?]", edit_admin_announcement_path(draft)
  end

  test "the admin dashboard links to 공지 관리" do
    sign_in(@admin)
    get admin_dashboard_path
    assert_select "a[href=?]", admin_announcements_path, minimum: 2
  end

  test "notices are not service desk tickets" do
    notice!("공지")
    assert_equal 0, ServiceDeskRequest.count
    assert_not_includes Announcement.reflect_on_all_associations.map(&:class_name), "ServiceDeskRequest"
  end
end
