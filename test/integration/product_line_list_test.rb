require "test_helper"

# Handoff 0068 -- the customer product list (/products): only listed (public, published)
# ProductLines, and the same access judgment the detail page's purchase box uses
# (ProductLine#access_state / #owned_by?), so the list and the detail page can never
# disagree about a product's state.
class ProductLineListTest < ActionDispatch::IntegrationTest
  ENV_KEYS = %w[LEEDOX_COMMERCE_ENABLED PAYMENT_PROVIDER PORTONE_API_SECRET PORTONE_STORE_ID PORTONE_CHANNEL_KEY
                PORTONE_KAKAOPAY_CHANNEL_KEY PORTONE_WEBHOOK_SECRET BANK_TRANSFER_ACCOUNT_INFO].freeze

  setup do
    Commerce::CatalogBootstrap.call!
    @previous_env = ENV_KEYS.to_h { |key| [ key, ENV[key] ] }
    ENV_KEYS.each { |key| ENV.delete(key) }
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    @admin = User.create!(name: "관리자", email: "list-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
  end

  teardown { @previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value } }

  def sign_in(user) = post(user_session_path, params: { user: { email: user.email, password: "password123" } })

  def open_sale!(line, amount)
    Commerce::ProductLineSales.set_price!(product_line: line, total_amount: amount, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: line, actor: @admin)
    line.reload
  end

  test "only public, published product lines are listed, oldest first -- drafts, unlisted and private are absent even for a signed-in admin" do
    old = ProductLine.create!(internal_name: "old", customer_name: "먼저 만든 제품", slug: "list-old", introduction: "소개", status: "published")
    new = ProductLine.create!(internal_name: "new", customer_name: "나중에 만든 제품", slug: "list-new", introduction: "소개", status: "published")
    draft = ProductLine.create!(internal_name: "d", customer_name: "초안 제품", slug: "list-draft", introduction: "소개", status: "draft")
    unlisted = ProductLine.create!(internal_name: "u", customer_name: "링크 전용 제품", slug: "list-unlisted", introduction: "소개", status: "published", visibility: "unlisted")
    private_line = ProductLine.create!(internal_name: "p", customer_name: "비공개 제품", slug: "list-private", introduction: "소개", status: "published", visibility: "private")

    get products_path
    assert_response :success
    assert_select "a[href=?]", product_line_path(old.slug)
    assert_select "a[href=?]", product_line_path(new.slug)
    assert_select "a[href=?]", product_line_path(draft.slug), 0
    assert_select "a[href=?]", product_line_path(unlisted.slug), 0
    assert_select "a[href=?]", product_line_path(private_line.slug), 0

    # oldest first (same order the admin list uses -- no separate position column)
    positions = css_select("main a[href^='/products/']").map { |a| a["href"] }
    assert_operator positions.index(product_line_path(old.slug)), :<, positions.index(product_line_path(new.slug))

    sign_in(@admin)
    get products_path
    assert_select "a[href=?]", product_line_path(draft.slug), 0
  end

  test "an empty list shows one line of copy instead of an empty grid" do
    ProductLine.update_all(status: "draft")
    get products_path
    assert_response :success
    assert_match(/공개될 예정|공개됩니다/, css_select("main").text)
  end

  test "each card shows the cover (or none), the name, the summary only when present, the published episode count, and links straight to the product -- never a link inside a link" do
    with_cover = ProductLine.create!(internal_name: "c", customer_name: "표지 있는 제품", slug: "list-cover", introduction: "소개", status: "published", summary: "한 줄로 설명하는 요약")
    with_cover.cover_image.attach(io: file_fixture("covers/cover.jpg").open, filename: "c.jpg", content_type: "image/jpeg")
    with_cover.update!(cover_image_alt: "표지")
    with_cover.content_episodes.create!(position: 1, customer_title: "공개된 편", status: "published")
    with_cover.content_episodes.create!(position: 2, customer_title: "초안 편", status: "draft")

    without_cover = ProductLine.create!(internal_name: "n", customer_name: "표지 없는 제품", slug: "list-no-cover", introduction: "소개", status: "published")

    get products_path
    assert_select "a[href=?]", product_line_path(with_cover.slug) do
      assert_select "img[alt=?]", "표지"
      assert_select "h2", text: "표지 있는 제품"
      assert_select "p", text: "한 줄로 설명하는 요약"
      assert_select "p", text: "공개 1편"
    end
    assert_select "a[href=?]", product_line_path(without_cover.slug) do
      assert_select "img", 0
      assert_select "p", text: /^공개 0편$/
    end
    assert_no_match(/\(제목 없음\)|초안 편/, css_select("main").text)
  end

  test "a summary left blank is simply not rendered as its own line" do
    line = ProductLine.create!(internal_name: "s", customer_name: "요약 없는 제품", slug: "list-no-summary", introduction: "소개", status: "published")
    get products_path
    assert_select "a[href=?] p", product_line_path(line.slug), text: "공개 0편"
  end

  test "price/access badges match the detail page's purchase box exactly, for every state" do
    free_open = ProductLine.create!(internal_name: "f", customer_name: "무료 제품", slug: "list-free", introduction: "소개", status: "published")
    open_sale!(free_open, 0)

    for_sale = ProductLine.create!(internal_name: "p", customer_name: "유료 제품", slug: "list-paid", introduction: "소개", status: "published")
    open_sale!(for_sale, 12_000)

    stopped = ProductLine.create!(internal_name: "st", customer_name: "중지된 제품", slug: "list-stopped", introduction: "소개", status: "published")
    Commerce::ProductLineSales.set_price!(product_line: stopped, total_amount: 5_000, actor: @admin)

    ungated = ProductLine.create!(internal_name: "g", customer_name: "무상품 제품", slug: "list-ungated", introduction: "소개", status: "published")

    holder = User.create!(name: "보유", email: "list-holder@example.com", password: "password123", created_at: 30.days.ago)
    Commerce::ClaimFreeAccess.call!(user: holder, product_line: free_open.reload)

    get products_path
    assert_select "a[href=?] span", product_line_path(free_open.slug), text: "무료"
    assert_select "a[href=?] span", product_line_path(for_sale.slug), text: "12,000원"
    assert_select "a[href=?] span", product_line_path(stopped.slug), text: "준비 중"
    # no commerce Product at all -- the detail page's purchase box renders nothing, so the list shows no badge either
    assert_select "a[href=?] span.rounded-full", product_line_path(ungated.slug), 0

    # the list and the detail page must show a guest the same underlying state (0068c) --
    # the exact wording differs (a badge vs. the full purchase box), never the judgment.
    { free_open => "로그인하고 무료로 시작", for_sale => "구매하기", stopped => "현재 구매할 수 없습니다" }.each do |line, detail_text|
      get product_line_path(line.slug)
      assert_includes css_select("#product-purchase").text, detail_text, "#{line.slug}: detail page"
    end

    sign_in(holder)
    get products_path
    assert_select "a[href=?] span", product_line_path(free_open.slug), text: "이용 중"
    get product_line_path(free_open.slug)
    assert_match(/무료로 이용 중인 제품입니다/, css_select("#product-purchase").text)
  end

  test "the header's product link and the detail page's back-to-list link both point at /products" do
    line = ProductLine.create!(internal_name: "n", customer_name: "제품", slug: "list-nav", introduction: "소개", status: "published")
    get product_line_path(line.slug)
    assert_select "header nav[aria-label='주요 내비게이션'] a[href=?]", products_path, text: "제품"
    assert_select "nav[aria-label='모바일 내비게이션'] a[href=?]", products_path, text: "제품"
    assert_select "a[href=?]", products_path, text: "← 제품 목록"
  end

  # --- R2: filter tabs --------------------------------------------------------

  test "a card with no cover image gets a decorative, same-aspect-ratio placeholder -- never a broken img" do
    line = ProductLine.create!(internal_name: "n", customer_name: "표지 없는 제품", slug: "list-placeholder", introduction: "소개", status: "published")
    get products_path
    assert_select "a[href=?]", product_line_path(line.slug) do
      assert_select "img", 0
      assert_select "div[aria-hidden='true'].aspect-video", 1
    end
  end

  test "the mine option only exists for a signed-in user, and a guest asking for it anyway falls back to all" do
    user = User.create!(name: "일반", email: "list-plain-#{SecureRandom.hex(3)}@example.com", password: "password123")
    get products_path
    assert_no_match(/내 제품/, css_select("nav[aria-label='제품 필터']").text)

    get products_path(filter: "mine")
    assert_response :success
    assert_select "nav[aria-label='제품 필터'] a.bg-indigo-600", text: /^전체/

    sign_in(user)
    get products_path
    assert_match(/내 제품/, css_select("nav[aria-label='제품 필터']").text)
  end

  test "an unrecognized filter value falls back to all instead of erroring" do
    line = ProductLine.create!(internal_name: "n", customer_name: "제품", slug: "list-fallback", introduction: "소개", status: "published")
    get products_path(filter: "bogus")
    assert_response :success
    assert_select "a[href=?]", product_line_path(line.slug)
    assert_select "nav[aria-label='제품 필터'] a.bg-indigo-600", text: /^전체/
  end

  test "free/paid/mine reuse access_state exactly -- a product already owned counts by what it costs, not just its exact badge" do
    free_open = ProductLine.create!(internal_name: "f", customer_name: "무료 제품", slug: "list-r2-free", introduction: "소개", status: "published")
    open_sale!(free_open, 0)
    for_sale = ProductLine.create!(internal_name: "p", customer_name: "유료 제품", slug: "list-r2-paid", introduction: "소개", status: "published")
    open_sale!(for_sale, 12_000)
    stopped = ProductLine.create!(internal_name: "s", customer_name: "중지된 제품", slug: "list-r2-stopped", introduction: "소개", status: "published")
    Commerce::ProductLineSales.set_price!(product_line: stopped, total_amount: 5_000, actor: @admin)
    ungated = ProductLine.create!(internal_name: "u", customer_name: "무상품 제품", slug: "list-r2-ungated", introduction: "소개", status: "published")

    get products_path(filter: "free")
    assert_select "a[href=?]", product_line_path(free_open.slug)
    assert_select "a[href=?]", product_line_path(for_sale.slug), 0
    assert_select "a[href=?]", product_line_path(stopped.slug), 0
    assert_select "a[href=?]", product_line_path(ungated.slug), 0

    get products_path(filter: "paid")
    assert_select "a[href=?]", product_line_path(for_sale.slug)
    assert_select "a[href=?]", product_line_path(free_open.slug), 0

    holder = User.create!(name: "보유", email: "list-r2-holder@example.com", password: "password123", created_at: 30.days.ago)
    Commerce::ClaimFreeAccess.call!(user: holder, product_line: free_open.reload)
    order = Commerce::OrderCreator.call!(user: holder, product_code: for_sale.reload.product.code,
      offer_code: for_sale.lifetime_offer.code, requested_start_on: nil, provider: "manual")
    Commerce::ConfirmManualPayment.call!(order: order, actor: @admin)
    sign_in(holder)

    # an owned free product stays under 무료, an owned paid product stays under 유료
    get products_path(filter: "free")
    assert_select "a[href=?]", product_line_path(free_open.slug)
    get products_path(filter: "paid")
    assert_select "a[href=?]", product_line_path(for_sale.slug)
    get products_path(filter: "mine")
    assert_select "a[href=?]", product_line_path(free_open.slug)
    assert_select "a[href=?]", product_line_path(for_sale.slug)
    assert_select "a[href=?]", product_line_path(stopped.slug), 0
  end

  test "each filter's empty state has its own copy and a link back to all" do
    ProductLine.update_all(status: "draft")
    line = ProductLine.create!(internal_name: "n", customer_name: "제품", slug: "list-r2-empty", introduction: "소개", status: "published")
    user = User.create!(name: "일반", email: "list-r2-empty@example.com", password: "password123")
    sign_in(user)

    get products_path(filter: "free")
    assert_match(/무료 제품이 아직 없습니다/, css_select("main").text)
    assert_select "a[href=?]", products_path, text: "전체 보기"

    get products_path(filter: "paid")
    assert_match(/유료 제품이 아직 없습니다/, css_select("main").text)

    get products_path(filter: "mine")
    assert_match(/아직 이용 중인 제품이 없습니다/, css_select("main").text)

    get products_path
    assert_no_match(/전체 보기/, css_select("main").text, "전체 has nothing to link back to")
    assert_select "a[href=?]", product_line_path(line.slug)
  end

  test "the option/badge counts use the same judgment as the cards they count" do
    ProductLine.create!(internal_name: "f", customer_name: "무료", slug: "list-r2-count-free", introduction: "소개", status: "published").tap { |l| open_sale!(l, 0) }
    2.times { |i| ProductLine.create!(internal_name: "p#{i}", customer_name: "유료#{i}", slug: "list-r2-count-paid-#{i}", introduction: "소개", status: "published").tap { |l| open_sale!(l, 1_000) } }

    get products_path
    counts = css_select("nav[aria-label='제품 필터'] a").to_h { |a| [ a.text.split.first, a.text.split.last.to_i ] }
    assert_equal counts["전체"], css_select("main a[href^='/products/']").size
    get products_path(filter: "free")
    assert_equal counts["무료"], css_select("main a[href^='/products/']").size
    get products_path(filter: "paid")
    assert_equal counts["유료"], css_select("main a[href^='/products/']").size
  end
end
