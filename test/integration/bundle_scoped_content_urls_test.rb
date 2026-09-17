require "test_helper"

# Handoff 0055 -- the core claim: two ContentBundles under the same Product
# each get their own 01..N episode numbering scope
# (/content/:product_code/:bundle_slug/:episode_id), so a second bundle no
# longer collides with the first the way a flat, product-wide position list
# did (see result.md §2, and handoff 0054 R2's P0-4 investigation that led
# here).
class BundleScopedContentUrlsTest < ActionDispatch::IntegrationTest
  setup do
    @product = Product.create!(code: "content_lab", name: "Content Lab", active: true)
  end

  # DB content is license-only (no guest/trial preview, see result.md §2.2-B) --
  # every read here needs a licensed session, unlike aistart/aigravity below
  # which allow some guest access by design.
  def sign_in_licensed_user
    user = User.create!(name: "테스트 유저", email: "bundle-scoped-#{SecureRandom.hex(4)}@example.com", password: "password123")
    today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
    end_date = today + 1.month
    License.create!(
      user: user, product: @product, source: "paid", status: "active",
      starts_on: today, last_usable_on: end_date - 1.day,
      access_ends_at: Commerce::PeriodCalculator::KST.local(end_date.year, end_date.month, end_date.day)
    )
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def publish_bundle_with_episodes(slug, internal_name, episode_bodies)
    bundle = ContentBundle.create!(product: @product, internal_name: internal_name, slug: slug, status: "published")
    episode_bodies.each_with_index do |body, index|
      bundle.content_episodes.create!(position: index + 1, customer_title: "#{internal_name} #{index + 1}편", body: body, status: "published")
    end
    bundle
  end

  test "two bundles under the same product both have an episode 01, and each URL reaches the correct one" do
    bundle_a = publish_bundle_with_episodes("bundle-a", "묶음 A", [ "A 묶음 첫 번째 편 본문", "A 묶음 두 번째 편 본문" ])
    bundle_b = publish_bundle_with_episodes("bundle-b", "묶음 B", [ "B 묶음 첫 번째 편 본문", "B 묶음 두 번째 편 본문" ])
    sign_in_licensed_user

    get "/content/content_lab/bundle-a/01"
    assert_response :success
    assert_match(/A 묶음 첫 번째 편 본문/, response.body)
    assert_no_match(/B 묶음/, response.body)

    get "/content/content_lab/bundle-b/01"
    assert_response :success
    assert_match(/B 묶음 첫 번째 편 본문/, response.body)
    assert_no_match(/A 묶음/, response.body)

    assert_equal 2, bundle_a.content_episodes.count
    assert_equal 2, bundle_b.content_episodes.count
    assert_equal [ 1, 2 ], bundle_a.content_episodes.order(:position).pluck(:position)
    assert_equal [ 1, 2 ], bundle_b.content_episodes.order(:position).pluck(:position)
  end

  test "Product index lists both published bundles; each bundle index lists only its own episodes" do
    publish_bundle_with_episodes("bundle-a", "묶음 A", [ "A 본문" ])
    publish_bundle_with_episodes("bundle-b", "묶음 B", [ "B 본문" ])

    get "/content/content_lab"
    assert_response :success
    assert_match(/묶음 A/, response.body)
    assert_match(/묶음 B/, response.body)

    get "/content/content_lab/bundle-a"
    assert_response :success
    assert_match(/묶음 A 1편/, response.body)
    assert_no_match(/묶음 B/, response.body)
  end

  test "prev/next navigation stays within the same bundle -- the last episode of bundle-a has no next into bundle-b" do
    publish_bundle_with_episodes("bundle-a", "묶음 A", [ "A1", "A2" ])
    publish_bundle_with_episodes("bundle-b", "묶음 B", [ "B1" ])
    sign_in_licensed_user

    get "/content/content_lab/bundle-a/02"
    assert_response :success
    assert_select "a[href=?]", product_bundle_episode_path("content_lab", "bundle-a", "01")
    assert_select "a[href*='bundle-b']", count: 0
  end

  test "draft, in_review, unpublished and archived bundles are all hidden from the Product index and direct URL" do
    %w[draft in_review unpublished archived].each do |status|
      slug = "hidden-#{status.tr('_', '-')}"
      bundle = ContentBundle.create!(product: @product, internal_name: "숨김 #{status}", slug: slug, status: status)
      bundle.content_episodes.create!(position: 1, customer_title: "편", body: "본문", status: "published")

      get "/content/content_lab"
      assert_response :success
      assert_no_match(/숨김 #{status}/, response.body)

      get "/content/content_lab/#{slug}"
      assert_response :not_found

      get "/content/content_lab/#{slug}/01"
      assert_response :not_found
    end
  end

  test "draft, in_review, unpublished and archived episodes are hidden from their (published) bundle's index and direct URL" do
    bundle = ContentBundle.create!(product: @product, internal_name: "편 상태 테스트", slug: "episode-status-test", status: "published")
    %w[draft in_review unpublished archived].each_with_index do |status, index|
      episode = bundle.content_episodes.create!(position: index + 1, customer_title: "#{status} 편", body: "본문", status: status)

      get "/content/content_lab/episode-status-test"
      assert_response :success
      assert_no_match(/#{status} 편/, response.body)

      get "/content/content_lab/episode-status-test/#{episode.display_id}"
      assert_response :not_found
    end
  end

  test "the file-based products (Chatdox, Claudox, aistart, Antigravity) are entirely unaffected by the DB bundle routing branch" do
    get "/docs"
    assert_response :success
    get "/docs/01"
    assert_response :success

    get "/claudox/read"
    assert_response :success
    get "/claudox/read/01"
    assert_response :success

    get "/content/aistart"
    assert_response :success
    get "/content/aistart/01"
    assert_response :success

    get "/content/aigravity"
    assert_response :success
    get "/content/aigravity/01"
    assert_response :success
  end
end
