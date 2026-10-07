require "test_helper"

# Handoff 0086 -- the pricing page is gone: no 가격 in the header (any viewer, desktop menu and mobile panel, dark and
# light header), /pricing moves permanently to /products, and the dashboard drops its two trial banners while the
# trial itself (more chapters of the earlier products early on) still works. The home's earlier-product cards and
# the earlier products' own price blocks are unchanged.
class PricingRemovalTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @chatdox = Product.find_by!(code: "chatdox")
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def user!(created_at: 30.days.ago, role: :user)
    User.create!(name: "회원", email: "pr-#{SecureRandom.hex(3)}@example.com", password: "password123", role: role, created_at: created_at)
  end

  def menu_labels(nav) = css_select("nav[aria-label='#{nav}'] a").map { |a| a.text.strip }

  # --- /pricing ------------------------------------------------------------------------------------

  test "/pricing moves permanently to /products, for guests and members" do
    get "/pricing"
    assert_response :moved_permanently
    assert_redirected_to products_path

    sign_in(user!)
    get "/pricing"
    assert_response :moved_permanently
    assert_redirected_to products_path
  end

  test "the two links that used to go to /pricing go to /products directly" do
    sign_in(user!) # the cancel callback is for signed-in buyers
    get billing_cancel_path # a cancel callback without a product code (with one, it still returns to that checkout)
    assert_redirected_to products_path
    get billing_cancel_path(product_code: "chatdox")
    assert_match %r{/billing/checkout}, response.location # unchanged: back to that product's checkout (exact URL in the billing tests)

    get product_chapter_path("aistart", "08") # aistart's last chapter: the completion box
    assert_select "#aistart-completion-cta a[href=?]", products_path, text: "가이드 둘러보기"
    assert_select "a[href='/pricing']", 0
  end

  # --- the header ------------------------------------------------------------------------------------
  # Handoff 0098 -- LEEDOX 소개 right after 가이드 for everyone.

  test "guests: 시리즈 · 로그인 · 회원가입, no 가격 (desktop and mobile panel)" do
    get root_path
    assert_equal [ "가이드", "LEEDOX 소개", "로그인", "회원가입" ], menu_labels("주요 내비게이션")
    assert_equal [ "가이드", "LEEDOX 소개", "로그인", "회원가입" ], menu_labels("모바일 내비게이션")
    assert_select "header a", text: "가격", count: 0
  end

  test "members: 시리즈 · 대시보드 · 마이페이지 · 로그아웃, no 가격" do
    sign_in(user!)
    get products_path
    assert_equal [ "가이드", "LEEDOX 소개", "대시보드", "마이페이지", "로그아웃" ], menu_labels("주요 내비게이션")
    assert_equal [ "가이드", "LEEDOX 소개", "대시보드", "마이페이지", "로그아웃" ], menu_labels("모바일 내비게이션")
    assert_select "header a", text: "가격", count: 0
  end

  test "admins: only 가격 is gone, on the dark customer header and the light admin header" do
    sign_in(user!(role: :admin))
    expected = [ "가이드", "LEEDOX 소개", "대시보드", "서비스데스크", "참조", "사용자관리", "마이페이지", "로그아웃" ]
    [ root_path, admin_dashboard_path ].each do |path|
      get path
      assert_equal expected, menu_labels("주요 내비게이션"), path
      assert_equal expected, menu_labels("모바일 내비게이션"), path
      assert_select "header a[href=?]", "/pricing", 0
    end
  end

  # --- the dashboard's trial banners -------------------------------------------------------------------

  test "no trial banner within the first 7 days, and the trial still opens more Chatdox chapters" do
    fresh = user!(created_at: 1.day.ago)
    assert fresh.trial_active?
    sign_in(fresh)
    get dashboard_path
    assert_response :success
    assert_not_includes css_select("main").text, "무료 체험"

    guest_limit = ProductContent.for("chatdox").guest_chapter_limit
    trial_limit = ProductContent.for("chatdox").trial_chapter_limit
    assert_operator trial_limit, :>, guest_limit, "fixture: the trial opens more than a guest sees"
    beyond_guest = format("%02d", guest_limit + 1)
    get doc_path(beyond_guest)
    assert_response :success, "a trial member still reads chapter #{beyond_guest} (DocPolicy#view_as_trial?)"

    delete destroy_user_session_path
    sign_in(user!) # past the trial, no license
    get doc_path(beyond_guest)
    assert_redirected_to "#{chatdox_path}#pricing"
  end

  test "no 'trial ended' banner or 가격 보기 link 7-21 days after sign-up" do
    sign_in(user!(created_at: 10.days.ago))
    get dashboard_path
    assert_response :success
    main = css_select("main").first
    assert_not_includes main.text, "무료 체험 기간이 끝났습니다"
    assert_nil main.at_css("a[href='/pricing']")
    assert_not main.css("a").any? { |a| a.text.include?("가격 보기") }
  end

  # --- unchanged ---------------------------------------------------------------------------------------

  test "the home's earlier-product cards keep their badge, price line and order" do
    @chatdox.update!(sale_enabled: true)
    get root_path
    row = css_select("section[aria-labelledby='track-ai']").first
    view = ActionView::Base.empty
    view.extend(StandaloneProductsHelper)
    view.extend(ActionView::Helpers::NumberHelper)
    cards = Product.on_home.to_a.map do |product|
      card = row.css("a").find { |a| a.text.include?(product.name) }
      assert card, product.code
      assert_includes card.text.squish, "#{view.standalone_product_badge(product)} · #{view.standalone_product_price(product)}"
      [ product, row.css("a").index(card) ]
    end
    # The order the home has always used (PagesController#pricing_rank, kept): on sale, then free, then the rest.
    ranker = PagesController.new
    expected = cards.map(&:first).sort_by { |product| [ ranker.send(:pricing_rank, product), product.code ] }
    assert_equal expected.map(&:code), cards.sort_by(&:last).map { |product, _| product.code }
  end

  test "an earlier product's own page keeps its price block and buy buttons" do
    get chatdox_path
    assert_response :success
    assert_select "#pricing"
    assert_select "#pricing h2", text: /기간별 이용 안내/
  end
end
