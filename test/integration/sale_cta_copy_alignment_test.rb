require "test_helper"

class SaleCtaCopyAlignmentTest < ActionDispatch::IntegrationTest
  setup do
    @old_env = ENV["LEEDOX_COMMERCE_ENABLED"]
    Commerce::CatalogBootstrap.call!
    @chatdox = Product.find_by!(code: "chatdox")
    @claudox = Product.find_by!(code: "claudox")
  end

  teardown do
    ENV["LEEDOX_COMMERCE_ENABLED"] = @old_env
  end

  test "1. Chatdox hero and bottom CTA display confirmed copy and point to #pricing" do
    get chatdox_path
    assert_response :success

    # Hero CTA
    assert_select "a[href='#pricing']", text: "가격 및 이용 기간 보기"

    # Bottom CTA
    assert_select "a[href='#pricing']", text: "가격 및 이용 기간 확인"
  end

  test "2. Claudox hero displays confirmed copy and points to #pricing" do
    get claudox_path
    assert_response :success

    # Hero CTA
    assert_select "a[href='#pricing']", text: "가격 및 이용 기간 보기"

    # Background note copy alignment
    assert_select "p", text: "현재 공개된 챕터와 미리보기는 판매 여부와 관계없이 계속 읽을 수 있습니다."
  end

  test "3. Disabled checkout return link displays product-specific confirmed copy and destination" do
    disable_sales!

    # Chatdox disabled checkout
    get billing_checkout_path("chatdox")
    assert_response :success
    assert_select "a[href=?]", "#{chatdox_path}#pricing", text: "Chatdox 가격 및 이용 기간 보기"

    # Claudox disabled checkout
    get billing_checkout_path("claudox")
    assert_response :success
    assert_select "a[href=?]", "#{claudox_path}#pricing", text: "Claudox 가격 및 이용 기간 보기"
  end

  test "4. Active sale products retain period license purchase CTA" do
    enable_sales!

    get chatdox_path
    assert_response :success
    assert_select "a[href=?]", billing_checkout_path_for("chatdox"), text: "기간제 라이선스 구매"

    get claudox_path
    assert_response :success
    assert_select "a[href=?]", billing_checkout_path_for("claudox"), text: "기간제 라이선스 구매"
  end

  test "5. Disabled sale products display purchasing in preparation and hide purchase CTA" do
    disable_sales!

    get chatdox_path
    assert_response :success
    assert_select "span", text: "구매 준비 중"
    assert_select "a[href=?]", billing_checkout_path_for("chatdox"), count: 0

    get claudox_path
    assert_response :success
    assert_select "span", text: "구매 준비 중"
    assert_select "a[href=?]", billing_checkout_path_for("claudox"), count: 0
  end

  test "6. Public customer screens do not leave '가격과 준비 상태' or '판매 준비 상태' phrases when sales are enabled" do
    enable_sales!

    [ chatdox_path, claudox_path, root_path ].each do |path| # /pricing removed in 0086
      get path
      assert_response :success
      assert_no_match(/가격과 준비 상태/, response.body)
      assert_no_match(/판매 준비 상태와 무관하게/, response.body)
    end
  end

  test "7. Non-regression of home page and Aistart free product CTAs (the pricing summary page went in 0086)" do
    enable_sales!

    # Home page -- since handoff 0071 the products are whole-card links in the "AI와 함께 만들기" row, showing
    # /pricing's own sale state instead of a "자세히 보기" button.
    get root_path
    assert_response :success
    assert_select "a[href=?]", chatdox_path, text: /판매 중/
    assert_select "a[href=?]", claudox_path, text: /판매 중/

    # The pricing summary page is gone (0086): its address moves to the series list
    get "/pricing"
    assert_redirected_to products_path

    # Aistart free product CTA (shows on the last chapter)
    get product_chapter_path("aistart", "08")
    assert_response :success
    assert_select "a[href=?]", new_user_registration_path, text: "회원가입하고 실전 가이드 둘러보기"
  end

  private

  def enable_sales!
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    @chatdox.update!(sale_enabled: true)
    @claudox.update!(sale_enabled: true)
  end

  def disable_sales!
    ENV["LEEDOX_COMMERCE_ENABLED"] = "false"
    @chatdox.update!(sale_enabled: false)
    @claudox.update!(sale_enabled: false)
  end

  def billing_checkout_path_for(product_code)
    product_code.to_s == "chatdox" ? billing_checkout_path : billing_checkout_path(product_code)
  end
end
