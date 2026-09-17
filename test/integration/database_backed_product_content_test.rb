require "test_helper"

# Handoff 0053 R2 originally proved a flat /content/:product_code/:id DB
# episode reaches the customer screen. Handoff 0055 replaced that flat shape
# with Product -> Bundle -> Episode (see result.md §3) once a second bundle
# under the same product revealed a position collision, so this file now
# proves the same end-to-end claim through the bundle-scoped URLs instead.
class DatabaseBackedProductContentTest < ActionDispatch::IntegrationTest
  setup do
    @product = Product.create!(code: "content_lab", name: "Content Lab", active: true)
    @bundle = ContentBundle.create!(product: @product, internal_name: "R2 vertical slice pilot", slug: "vertical-slice-pilot", status: "published")
    @published_episode = ContentEpisode.create!(
      bundle: @bundle, position: 1, customer_title: "발행된 편",
      body: "# 발행된 편\n\nDB에서 바로 저작하고 게시한 본문입니다.", status: "published"
    )
    @draft_episode = ContentEpisode.create!(
      bundle: @bundle, position: 2, customer_title: "초안 편",
      body: "# 초안 편\n\n아직 검토 중인 본문입니다.", status: "draft"
    )
  end

  test "the Product index lists the published bundle, with zero hq/ files" do
    get "/content/content_lab"
    assert_response :success
    assert_match(/R2 vertical slice pilot/, response.body)
  end

  test "the bundle index lists the published episode but not the draft one" do
    get "/content/content_lab/vertical-slice-pilot"
    assert_response :success
    assert_match(/발행된 편/, response.body)
    assert_no_match(/초안 편/, response.body)
  end

  test "a draft episode is fully invisible -- not in the bundle index, and 404s on direct URL" do
    get "/content/content_lab/vertical-slice-pilot/02"
    assert_response :not_found
    assert_match(/아직 공개되지 않은 콘텐츠입니다/, response.body)
  end

  test "guest access is blocked (no numeric-chapter guest/trial preview for DB content)" do
    get "/content/content_lab/vertical-slice-pilot/01"
    assert_redirected_to new_user_session_path
  end

  test "a licensed user can read the published episode" do
    user = User.create!(name: "테스트 유저", email: "content-lab-#{SecureRandom.hex(3)}@example.com", password: "password123")
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    end_date = today + 1.month
    License.create!(
      user: user, product: @product, source: "paid", status: "active",
      starts_on: today, last_usable_on: end_date - 1.day,
      access_ends_at: Commerce::PeriodCalculator::KST.local(end_date.year, end_date.month, end_date.day)
    )
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    get "/content/content_lab/vertical-slice-pilot/01"
    assert_response :success
    assert_match(/DB에서 바로 저작하고 게시한 본문입니다/, response.body)
  end

  test "the old flat 2-segment DB episode URL now 404s as a bundle-slug lookup miss (handoff 0055 §4.4 -- no production publish history to preserve)" do
    get "/content/content_lab/01"
    assert_response :not_found
  end
end
