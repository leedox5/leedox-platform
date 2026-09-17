require "test_helper"

# Proves the core claim of handoff 0053 R2: a bundle/episode authored purely
# in the DB (no hq/<product_code>/ folder at all) reaches the real customer
# screen through the exact same routes/controller/policy stack as the
# filesystem-backed products -- see ProductContent::DatabaseSource and
# ProductContentController#show's @source.body(slug) call (result.md §2.2-A).
class DatabaseBackedProductContentTest < ActionDispatch::IntegrationTest
  setup do
    @product = Product.create!(code: "content_lab", name: "Content Lab", active: true)
    @bundle = ContentBundle.create!(product: @product, internal_name: "R2 vertical slice pilot", status: "published")
    @published_episode = ContentEpisode.create!(
      bundle: @bundle, position: 1, customer_title: "발행된 편",
      body: "# 발행된 편\n\nDB에서 바로 저작하고 게시한 본문입니다.", status: "published"
    )
    @draft_episode = ContentEpisode.create!(
      bundle: @bundle, position: 2, customer_title: "초안 편",
      body: "# 초안 편\n\n아직 검토 중인 본문입니다.", status: "draft"
    )
  end

  test "the bundle's episode list reaches the generic /content/:product_code route with zero hq/ files" do
    get "/content/content_lab"
    assert_response :success
    assert_match(/발행된 편/, response.body)
  end

  test "a draft episode is fully invisible -- not in the index, and 404s as 'not found' rather than 'not available' (R3 §5 fix)" do
    get "/content/content_lab"
    assert_response :success
    assert_no_match(/초안 편/, response.body)

    get "/content/content_lab/02"
    assert_response :not_found
    assert_match(/아직 공개되지 않은 콘텐츠입니다/, response.body)
  end

  test "guest access is blocked (no numeric-chapter guest/trial preview for DB content)" do
    get "/content/content_lab/01"
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

    get "/content/content_lab/01"
    assert_response :success
    assert_match(/DB에서 바로 저작하고 게시한 본문입니다/, response.body)
  end
end
