require "test_helper"

class AigravityLandingPageTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
  end

  test "renders /aigravity landing page with Emerald theme, starter badge, and 14 chapter links" do
    get aigravity_path
    assert_response :success

    # Emerald theme & title
    assert_select "title", text: /Antigravity \| 따라하며 배우는 무중력 AI 코딩 마스터클래스/
    assert_select "h1", text: /무중력 AI 코딩 마스터클래스/
    assert_select "p", text: /AI-NATIVE STARTER PACKAGE/

    # Hero free trial badge (matches trial_chapter_limit)
    # & CTA link to episode 01
    assert_equal 3, ProductContent.for("aigravity").trial_chapter_limit
    assert_select "a[href=?]", product_chapter_path("aigravity", "01"), text: /3 챕터 무료 체험 가능/
    assert_select "a[href=?]", product_chapter_path("aigravity", "01"), text: /무중력 코딩 시작하기/

    # 14 chapters across 4 phases
    doc = Nokogiri::HTML(response.body)
    (1..14).each do |id|
      padded_id = format("%02d", id)
      link = doc.at_css("a[href='#{product_chapter_path('aigravity', padded_id)}']")
      assert link, "expected curriculum link for chapter #{padded_id}"
    end

    # Pricing section
    assert_select "#pricing" do
      assert_select "h2", text: /기간별 이용 안내/
      assert_select "p", text: /준비 중이며 현재는 구매할 수 없습니다/
    end

    # Bottom Dark Banner & FAQ
    assert_select "h2", text: /지금 바로 무중력 AI 코딩 마스터클래스를 시작하세요/
    assert_select "h2", text: /자주 묻는 질문 \(FAQ\)/
    assert_select "code", text: "handoff/"
    assert_select "code", text: "handoff-agy/", count: 0
  end

  test "renders 4 pricing offer cards with Emerald theme and direct checkout CTAs when offers exist" do
    product = Product.find_by!(code: "aigravity")
    [ 1, 3, 6, 12 ].each do |months|
      ProductOffer.create!(
        product: product,
        code: "aigravity-#{months}m-v1",
        version: 1,
        duration_months: months,
        supply_amount: 10000 * months,
        vat_amount: 1000 * months,
        total_amount: 11000 * months,
        discount_bps: (months == 12 ? 2000 : (months == 6 ? 1000 : 0)),
        currency: "KRW",
        active: true
      )
    end

    get aigravity_path
    assert_response :success

    assert_select "#pricing" do
      [ 1, 3, 6, 12 ].each do |months|
        assert_select "article", text: /#{months}개월/ do
          assert_select "span", text: /#{months}개월 선택/
        end
      end
    end

    # When sales are enabled, the bottom checkout button uses the Emerald theme
    product.update!(active: true, sale_enabled: true)
    get aigravity_path
    assert_response :success
    assert_select "a[href=?]", billing_checkout_path(product_code: "aigravity"), text: /기간제 라이선스 구매/ do |elements|
      assert_includes elements.first["class"], "bg-emerald-600"
    end
  end

  test "pricing page links Antigravity product to /aigravity landing page" do
    user = User.create!(name: "Test User", email: "aigravity-user@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    get pricing_path
    assert_response :success
    assert_select "a[href=?]", aigravity_path, text: /자세히 보기/
  end

  test "enforces admin DB guest_chapter_limit and trial_chapter_limit overrides dynamically (handoff 0045 R2 & 0017)" do
    product = Product.find_by!(code: "aigravity")
    # guest_chapter_limit and trial_chapter_limit are separate columns now --
    # setting one must not move the other (that coupling was exactly the bug
    # 0045 investigated and R2 fixed).
    product.update!(guest_chapter_limit: 2, trial_chapter_limit: 9)

    assert_equal 9, ProductContent.for("aigravity").trial_chapter_limit
    assert_equal 2, ProductContent.for("aigravity").guest_chapter_limit

    # Hero badge reflects updated trial_chapter_limit
    get aigravity_path
    assert_response :success
    assert_select "a[href=?]", product_chapter_path("aigravity", "01"), text: /9 챕터 무료 체험 가능/

    # Accessing chapter 02 is allowed as guest
    get product_chapter_path("aigravity", "02")
    assert_response :success

    # Accessing chapter 03 without a license redirects or blocks guest
    get product_chapter_path("aigravity", "03")
    assert_response :redirect
  end
end
