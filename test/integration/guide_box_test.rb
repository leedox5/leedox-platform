require "test_helper"

# Handoff 0092 R1 (D-012) -- the guide page's access box, shorter: a free guide not started yet is one line plus
# 이용하기 (the button does what it did), and in use is one line whatever the source -- a free starter no longer reads
# "구매한 …". The for-sale and closed boxes are unchanged. Who can open what is unchanged in R1.
class GuideBoxTest < ActionDispatch::IntegrationTest
  FREE_LINE = "지금은 모든 에피소드를 무료로 이용할 수 있습니다. 시작해 두면 계속 볼 수 있습니다."
  GONE = [ "무료 · 무기한 이용", "결제나 주문 없이", "로그인하고 무료로 시작", "무료로 이용 시작", "무기한 이용", "구매한 가이드",
    "무료로 이용 중인", "모든 편과 산출물을 계속" ].freeze

  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "gb-adm-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @member = User.create!(name: "회원", email: "gb-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    @free = guide!("free-guide", 0)
    @paid = guide!("paid-guide", 1_100)
  end

  def guide!(slug, amount)
    line = ProductLine.create!(internal_name: slug, customer_name: "가이드 #{slug}", slug: slug, introduction: "소개", status: "published")
    line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문", status: "published")
    Commerce::ProductLineSales.set_price!(product_line: line, total_amount: amount, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: line.reload, actor: @admin)
    line.reload
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def box = css_select("#product-purchase").first
  def box_text = box.text.squish

  def assert_free_not_started
    assert_equal "#{FREE_LINE} 이용하기", box_text
    GONE.each { |gone| assert_not_includes box_text, gone }
  end

  test "a guest on a free guide: one line and 이용하기, still going to the checkout (sign in first)" do
    get product_line_path("free-guide")
    assert_free_not_started
    link = box.at_css("a")
    assert_equal billing_checkout_path(@free.product.code), link["href"]
    get link["href"]
    assert_redirected_to new_user_session_path
  end

  test "a member who hasn't started a free guide: the same line, 이용하기 still starts it" do
    sign_in(@member)
    get product_line_path("free-guide")
    assert_free_not_started
    assert_select "#product-purchase form[action=?] button", claim_free_access_path(@free.product.code), text: "이용하기"
    assert_difference -> { License.where(user: @member, product: @free.product).count }, 1 do
      post claim_free_access_path(@free.product.code)
    end
  end

  test "in use after a free start: one line, no button" do
    sign_in(@member)
    post claim_free_access_path(@free.product.code)
    get product_line_path("free-guide")
    assert_equal "이용 중인 가이드입니다.", box_text
    assert_nil box.at_css("a, button, form")
  end

  test "in use after a purchase: the same one line (no 구매한 …)" do
    sign_in(@member)
    order = Commerce::OrderCreator.call!(user: @member, product_code: @paid.product.code, offer_code: @paid.lifetime_offer.code,
      requested_start_on: nil, provider: "manual")
    Commerce::ConfirmManualPayment.call!(order: order, actor: @admin)
    get product_line_path("paid-guide")
    assert_equal "이용 중인 가이드입니다.", box_text
  end

  test "a free starter whose guide got a price later also reads 이용 중 (backlog 0065, on the detail page)" do
    sign_in(@member)
    post claim_free_access_path(@free.product.code)
    Commerce::ProductLineSales.set_price!(product_line: @free, total_amount: 2_200, actor: @admin)
    get product_line_path("free-guide")
    assert_equal "이용 중인 가이드입니다.", box_text
  end

  test "the for-sale box is unchanged, for guests and members" do
    [ nil, @member ].each do |user|
      sign_in(user) if user
      get product_line_path("paid-guide")
      assert_includes box_text, "한 번 결제 · 무기한 이용"
      assert_includes box_text, "1,100원 (VAT 포함)"
      assert_select "#product-purchase a[href=?]", billing_checkout_path(@paid.product.code), text: "구매하기"
      assert_includes box_text, "구매하면 이 가이드의 모든 편과 산출물을 이용할 수 있습니다. 다른 가이드는 포함되지 않습니다."
    end
  end

  test "the closed box is unchanged" do
    @free.product.update!(sale_enabled: false)
    get product_line_path("free-guide")
    assert_equal "현재 시작할 수 없습니다 이 가이드는 준비 중이거나 이용 시작이 중지되었습니다. 이미 이용 중인 분은 로그인하면 계속 이용하실 수 있습니다.", box_text
  end

  test "an admin sees the box by their own license, like a member" do
    sign_in(@admin)
    get product_line_path("free-guide")
    assert_free_not_started
  end
end
