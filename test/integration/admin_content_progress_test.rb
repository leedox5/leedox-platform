require "test_helper"

class AdminContentProgressTest < ActionDispatch::IntegrationTest
  test "guests and non-admins are blocked, admins see accurate Chatdox and Claudox progress grouped by phase" do
    user = User.create!(name: "테스트 유저", email: "content-progress-user@example.com", password: "password123")
    admin = User.create!(name: "테스트 유저", email: "content-progress-admin@example.com", password: "password123", role: :admin)

    get admin_content_progress_path
    assert_redirected_to new_user_session_path

    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    get admin_content_progress_path
    assert_redirected_to root_path
    delete destroy_user_session_path

    post user_session_path, params: { user: { email: admin.email, password: "password123" } }
    get admin_content_progress_path
    assert_response :success

    chatdox_done = ProductContent.for("chatdox").chapters.count { |chapter| chapter[:available] }
    claudox_rows = File.read(Rails.root.join("hq/claudox/88_progress.md")).scan(Admin::ContentProgressController::CLAUDOX_ROW_PATTERN)
    claudox_done = claudox_rows.count { |_title, _id, status| status == "✅" }
    # 88_progress.md now also carries a "부록" tracking row (id 90) alongside
    # the regular 1..20 table; CLAUDOX_ROW_PATTERN matches both tables
    # indiscriminately, and Admin::ContentProgressController's badge counts
    # every matched row (hence claudox_rows.size, not a hardcoded 20) while
    # its Part 1/2/3 grouping only ever displays ids within a phase range.
    # Admin screens are out of scope for the appendix-chapters round -- this
    # is just keeping the assertions honest about that existing behavior.
    claudox_phase_rows = claudox_rows.select { |_title, id, _status| (1..20).cover?(id.to_i) }

    assert_match(/#{chatdox_done}\s*\/\s*20/, response.body)
    assert_match(/#{claudox_done}\s*\/\s*#{claudox_rows.size}/, response.body)

    doc = Nokogiri::HTML(response.body)
    cards = doc.css("article")
    assert_equal 2, cards.size, "expected one card per product"

    [
      [ cards[0], ProductContent.for("chatdox").chapters.map { |c| c.merge(done: c[:available]) }, ProductContent.for("chatdox").phases, "doc_path" ],
      [ cards[1], claudox_phase_rows.map { |title, id, status| { id: id, title: title, done: status == "✅" } }, ProductContent.for("claudox").phases, "claudox_chapter_path" ]
    ].each do |card, chapters, phases, path_helper|
      # No percent or last-modified data should leak into this page anymore.
      assert_no_match(/\d+%/, card.text)
      assert_no_match(/\d{4}년 \d{1,2}월 \d{1,2}일/, card.text)

      phase_headers = card.css("h3").map(&:text)
      assert_equal phases.map { |phase| "#{phase[:label]} · #{phase[:title]}" }, phase_headers

      chapters.each do |chapter|
        row = card.css("li").find { |li| li.text.include?(chapter[:title]) }
        assert row, "expected a row for #{chapter[:title]} in #{path_helper}'s card"

        link = row.at_css("a")
        assert_equal "#{chapter[:id]}. #{chapter[:title]}", link.text
        expected_path = path_helper == "doc_path" ? doc_path(chapter[:id]) : claudox_chapter_path(chapter[:id])
        assert_equal expected_path, link["href"]
        assert_equal chapter[:done], row.text.include?("✅")
      end
    end
  end

  test "admin dashboard links to the content progress page" do
    admin = User.create!(name: "테스트 유저", email: "content-progress-dash-admin@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    get admin_dashboard_path

    assert_response :success
    assert_select "a[href=?]", admin_content_progress_path, text: "콘텐츠 진행 현황"
  end
end
