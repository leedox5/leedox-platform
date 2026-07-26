require "test_helper"

class ChapterLastUpdatedTimestampTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
  end

  test "Chatdox chapter page shows the manifest-derived KST timestamp, not raw (likely UTC) filesystem mtime" do
    expected = I18n.l(ProductContent.for("chatdox").last_updated_at("01_overview"), format: :long, locale: :ko)

    get doc_path("01")
    assert_response :success
    assert_match(/최종 업데이트: #{Regexp.escape(expected)}/, response.body)
  end

  test "Claudox chapters with different manifest commit dates show their own distinct KST timestamps (not a shared deploy-checkout time)" do
    user = User.create!(name: "테스트 유저", email: "last-updated-appendix@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    product = Product.find_by!(code: "claudox")
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    end_date = today + 1.month
    License.create!(
      user: user, product: product, source: "paid", status: "active",
      starts_on: today, last_usable_on: end_date - 1.day,
      access_ends_at: Commerce::PeriodCalculator::KST.local(end_date.year, end_date.month, end_date.day)
    )

    # Deliberately not hardcoded to specific chapter numbers -- HQ content
    # syncs regularly touch several chapters in the same commit (they'd then
    # share a timestamp and silently make this test meaningless), so find
    # whichever pair currently has distinct commit dates in the real
    # manifest instead of assuming particular chapters do.
    claudox_source = ProductContent.for("claudox")
    chapter_a, chapter_b = claudox_source.chapters.combination(2).find do |a, b|
      claudox_source.last_updated_at(a[:slug]) != claudox_source.last_updated_at(b[:slug])
    end
    assert chapter_a, "expected at least two Claudox chapters with different manifest commit dates"

    expected_a = I18n.l(claudox_source.last_updated_at(chapter_a[:slug]), format: :long, locale: :ko)
    expected_b = I18n.l(claudox_source.last_updated_at(chapter_b[:slug]), format: :long, locale: :ko)

    get claudox_chapter_path(chapter_a[:id])
    assert_response :success
    assert_match(/최종 업데이트: #{Regexp.escape(expected_a)}/, response.body)

    get claudox_chapter_path(chapter_b[:id])
    assert_response :success
    assert_match(/최종 업데이트: #{Regexp.escape(expected_b)}/, response.body)
  end
end
