require "test_helper"

class ChapterLastUpdatedTimestampTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
  end

  test "Chatdox chapter page shows the manifest-derived KST timestamp, not raw (likely UTC) filesystem mtime" do
    expected = I18n.l(Curriculum.last_updated_at("01_overview"), format: :long, locale: :ko)

    get doc_path("01")
    assert_response :success
    assert_match(/최종 업데이트: #{Regexp.escape(expected)}/, response.body)
  end

  test "Claudox appendix chapters 90 and 91 show their own distinct KST timestamps (not a shared deploy-checkout time)" do
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

    expected_90 = I18n.l(Claudox.last_updated_at("90_session_mechanics"), format: :long, locale: :ko)
    expected_91 = I18n.l(Claudox.last_updated_at("91_time_and_identity"), format: :long, locale: :ko)
    assert_not_equal expected_90, expected_91,
      "fixture assumption broken: 90 and 91's manifest entries are no longer distinct -- update this test's fixtures"

    get claudox_chapter_path("90")
    assert_response :success
    assert_match(/최종 업데이트: #{Regexp.escape(expected_90)}/, response.body)

    get claudox_chapter_path("91")
    assert_response :success
    assert_match(/최종 업데이트: #{Regexp.escape(expected_91)}/, response.body)
  end
end
