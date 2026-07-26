require "test_helper"

class ClaudoxAppendixChaptersTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
  end

  test "the appendix section is listed on /claudox/read, separate from the Part 1/2/3 groups" do
    get claudox_read_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    assert_match(/부록/, response.body)
    assert_match(/세션의 정체를 캐다/, response.body)

    # Not grouped under any Part -- only the appendix "details" card mentions it.
    part_cards = doc.css("div.space-y-4 > details").reject { |d| d.at_css("p.text-xs")&.text == "부록" }
    part_cards.each do |card|
      assert_no_match(/세션의 정체를 캐다/, card.text)
    end
  end

  test "a guest cannot open an appendix chapter" do
    get claudox_chapter_path("90")
    assert_redirected_to new_user_session_path
  end

  test "a Trial-only user cannot open an appendix chapter even though Trial covers chapters 1..5" do
    user = User.create!(name: "테스트 유저", email: "appendix-trial@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    assert user.trial_active?

    get claudox_chapter_path("90")
    assert_redirected_to root_path
  end

  test "a Claudox-licensed user can open an appendix chapter, and it has no completion UI" do
    user = User.create!(name: "테스트 유저", email: "appendix-licensed@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    product = Product.find_by!(code: "claudox")
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    end_date = today + 1.month
    License.create!(
      user: user, product: product, source: "paid", status: "active",
      starts_on: today, last_usable_on: end_date - 1.day,
      access_ends_at: Commerce::PeriodCalculator::KST.local(end_date.year, end_date.month, end_date.day)
    )

    get claudox_chapter_path("90")
    assert_response :success
    assert_match(/세션의 정체를 캐다/, response.body)
    assert_no_match(/학습 상태/, response.body)
    assert_no_match(/이 챕터 완료/, response.body)
  end

  test "attempting to mark an appendix chapter complete via a crafted request is rejected, not a 500" do
    user = User.create!(name: "테스트 유저", email: "appendix-crafted@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    product = Product.find_by!(code: "claudox")
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    end_date = today + 1.month
    License.create!(
      user: user, product: product, source: "paid", status: "active",
      starts_on: today, last_usable_on: end_date - 1.day,
      access_ends_at: Commerce::PeriodCalculator::KST.local(end_date.year, end_date.month, end_date.day)
    )

    post chapter_progresses_path, params: { chapter_id: "90", product_code: "claudox" }
    assert_response :not_found
    assert_nil user.chapter_progresses.find_by(chapter_id: "90", product_code: "claudox")
  end

  test "Chatdox access policy has no regression: docs 01..20 guest/trial/license behavior unchanged" do
    get doc_path("02")
    assert_response :success

    get doc_path("03")
    assert_redirected_to new_user_session_path

    user = User.create!(name: "테스트 유저", email: "appendix-chatdox-regress@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    get doc_path("05")
    assert_response :success
    get doc_path("06")
    assert_redirected_to root_path

    product = Product.find_by!(code: "chatdox")
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    end_date = today + 1.month
    License.create!(
      user: user, product: product, source: "paid", status: "active",
      starts_on: today, last_usable_on: end_date - 1.day,
      access_ends_at: Commerce::PeriodCalculator::KST.local(end_date.year, end_date.month, end_date.day)
    )
    get doc_path("20")
    assert_response :success
  end

  test "Chatdox never serves a 90-range id -- unaffected by the appendix range extension" do
    get doc_path("90")
    assert_response :not_found
  end
end
