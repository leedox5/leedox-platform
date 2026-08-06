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
    # 88_progress.md's "부록 (특별판)" table (ids 90/91) uses the exact same
    # column shape as the regular chapter tables, so CLAUDOX_ROW_PATTERN
    # matches both indiscriminately -- the controller filters to
    # CLAUDOX_CHAPTER_RANGE (1..20) so appendix rows never inflate the total
    # or leak into a phase group. See handoff 0022.
    claudox_phase_rows = claudox_rows.select { |_title, id, _status| Admin::ContentProgressController::CLAUDOX_CHAPTER_RANGE.cover?(id.to_i) }
    claudox_done = claudox_phase_rows.count { |_title, _id, status| status == "✅" }

    assert_match(/#{chatdox_done}\s*\/\s*20/, response.body)
    assert_match(/#{claudox_done}\s*\/\s*20/, response.body)

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

  test "appendix rows (부록, ids 90/91) never appear as a Claudox chapter row" do
    admin = User.create!(name: "테스트 유저", email: "content-progress-appendix-admin@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    get admin_content_progress_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    claudox_card = doc.css("article")[1]
    appendix_titles = File.read(Rails.root.join("hq/claudox/88_progress.md"))
      .scan(Admin::ContentProgressController::CLAUDOX_ROW_PATTERN)
      .reject { |_title, id, _status| Admin::ContentProgressController::CLAUDOX_CHAPTER_RANGE.cover?(id.to_i) }
      .map(&:first)
    assert appendix_titles.any?, "expected 88_progress.md to still have at least one 부록 row to test against"

    appendix_titles.each do |title|
      assert_nil claudox_card.css("li").find { |li| li.text.include?(title) },
        "expected no row for appendix chapter #{title.inspect}"
    end
  end

  test "CLAUDOX_ROW_PATTERN recognizes 🔵 as a status, counted as not-done" do
    sample = <<~MARKDOWN
      | # | 챕터 | 파일 | 완성도 | 상태 |
      |---|------|------|:---:|:---:|
      | 15 | 진행 중인 이야기 | [15_pull_request.md](15_pull_request.md) | 70% | 🔵 |
    MARKDOWN

    rows = sample.scan(Admin::ContentProgressController::CLAUDOX_ROW_PATTERN)
    assert_equal 1, rows.size, "🔵 row should still match the pattern, not silently disappear"

    title, id, status = rows.first
    assert_equal "15", id
    assert_equal "🔵", status
    assert_not_equal "✅", status # done: status == "✅" still marks 🔵 as not-done, which is correct
  end

  test "admin dashboard links to the content progress page" do
    admin = User.create!(name: "테스트 유저", email: "content-progress-dash-admin@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    get admin_dashboard_path

    assert_response :success
    assert_select "a[href=?]", admin_content_progress_path, text: "콘텐츠 진행 현황"
  end
end
