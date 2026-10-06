require "test_helper"

# Handoff 0093 -- a guide page without an image puts the name, the one-line summary and the access box into one header
# box (the box's own contents below a thin rule; same contents and conditions as 0092). A guide with an image is as
# before, and so is one without a commerce product (no access box to put in). "Has an image" is the branch that draws
# it; the admin preview always draws one (cover or placeholder), so it never gets the header box.
class GuideHeaderBoxTest < ActionDispatch::IntegrationTest
  FREE_LINE = "지금은 모든 에피소드를 무료로 이용할 수 있습니다. 시작해 두면 계속 볼 수 있습니다."

  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "hb-adm-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @member = User.create!(name: "회원", email: "hb-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    @free = guide!("free-guide", 0)
    @paid = guide!("paid-guide", 1_100)
  end

  def guide!(slug, amount)
    line = ProductLine.create!(internal_name: slug, customer_name: "가이드 #{slug} 설치부터 내 프로젝트까지", slug: slug,
      summary: "한 줄 요약 #{slug}", introduction: "소개", status: "published")
    line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문", status: "published", open_preview: true)
    line.content_episodes.create!(position: 2, customer_title: "둘째 편", body: "본문", status: "published")
    Commerce::ProductLineSales.set_price!(product_line: line, total_amount: amount, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: line.reload, actor: @admin)
    line.reload
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def header = css_select("[data-guide-header]").first
  def box_text = css_select("[data-guide-header] #product-purchase").first.text.squish

  # name -> summary -> the access box (bare, below a thin rule), all inside the header box; nothing else in it
  def assert_header_box(name, summary)
    assert header, "a header box"
    kids = header.element_children
    assert_equal %w[h1 p section], kids.map(&:name)
    assert_equal name, kids[0].text.strip
    assert_equal summary, kids[1].text.strip
    assert_equal "product-purchase", kids[2]["id"]
    rule = kids[2]["class"].split
    assert_includes rule, "border-t"
    assert_not_includes rule, "rounded-2xl"
    assert_equal 1, css_select("#product-purchase").size, "no second access box outside"
    assert_equal "main", header.parent.name
    html = css_select("main").first.to_html
    assert_operator html.index("data-guide-header"), :<, html.index("가이드 바로가기"), "the section links stay under the box"
    assert_operator html.index("가이드 바로가기"), :<, html.index('id="intro"')
  end

  # --- without an image: the header box, every state ----------------------------------------------------------

  test "guest, free: name, summary, then the free line, 이용하기 and the E01 line" do
    get product_line_path("free-guide")
    assert_header_box("가이드 free-guide 설치부터 내 프로젝트까지", "한 줄 요약 free-guide")
    assert_equal "#{FREE_LINE} 이용하기 E01은 로그인 없이 볼 수 있습니다.", box_text
    assert_select "[data-guide-header] a[href=?]", product_continue_path("free-guide"), text: "이용하기"
  end

  test "member before use: the same box contents as the access box always had (no E01 line)" do
    sign_in(@member)
    get product_line_path("free-guide")
    assert_header_box("가이드 free-guide 설치부터 내 프로젝트까지", "한 줄 요약 free-guide")
    assert_equal "#{FREE_LINE} 이용하기", box_text
    assert_select "[data-guide-header] form[action=?] button", claim_free_access_path(@free.product.code), text: "이용하기"
  end

  test "in use: 이용 중인 가이드입니다." do
    sign_in(@member)
    post claim_free_access_path(@free.product.code)
    get product_line_path("free-guide")
    assert_header_box("가이드 free-guide 설치부터 내 프로젝트까지", "한 줄 요약 free-guide")
    assert_equal "이용 중인 가이드입니다.", box_text
  end

  test "closed: 현재 시작할 수 없습니다 + its sentence" do
    @free.product.update!(sale_enabled: false)
    get product_line_path("free-guide")
    assert header
    assert_equal "현재 시작할 수 없습니다 이 가이드는 준비 중이거나 이용 시작이 중지되었습니다. 이미 이용 중인 분은 로그인하면 계속 이용하실 수 있습니다.", box_text
  end

  test "paid: the paid box as it was, for a guest, a member and a buyer" do
    get product_line_path("paid-guide")
    assert_header_box("가이드 paid-guide 설치부터 내 프로젝트까지", "한 줄 요약 paid-guide")
    assert_includes box_text, "한 번 결제 · 무기한 이용"
    assert_includes box_text, "1,100원 (VAT 포함)"
    assert_includes box_text, "E01은 로그인 없이 볼 수 있습니다."
    sign_in(@member)
    get product_line_path("paid-guide")
    assert_includes box_text, "E01은 구매 전에 볼 수 있습니다."
    order = Commerce::OrderCreator.call!(user: @member, product_code: @paid.product.code, offer_code: @paid.lifetime_offer.code,
      requested_start_on: nil, provider: "manual")
    Commerce::ConfirmManualPayment.call!(order: order, actor: @admin)
    get product_line_path("paid-guide")
    assert_equal "이용 중인 가이드입니다.", box_text
  end

  test "name and summary break between words, still wrapping a single overlong word" do
    get product_line_path("free-guide")
    %w[break-keep break-words].each do |klass|
      assert_includes header.at_css("h1")["class"].split, klass
      assert_includes header.at_css("p")["class"].split, klass
    end
  end

  # --- unchanged ------------------------------------------------------------------------------------------------

  # Handoff 0095 -- with an image the header box too: the cover is its top (edge to edge, no rounding or margin of its
  # own -- the box's corners cut it), then name -> summary -> the bare access box under the same padding. One box.
  test "with an image: the cover tops the header box, then name, summary and the access box" do
    @free.cover_image.attach(io: file_fixture("covers/cover.jpg").open, filename: "c.jpg", content_type: "image/jpeg")
    @free.update!(cover_image_alt: "표지")
    get product_line_path("free-guide")
    assert header
    assert_equal "main", header.parent.name
    assert_equal header, css_select("main").first.element_children.first, "the box is the page's first block"
    assert_includes header["class"].split, "overflow-hidden"
    assert_includes header["class"].split, "rounded-2xl"
    kids = header.element_children
    assert_equal %w[img div], kids.map(&:name)
    img = kids[0]
    assert_equal "표지", img["alt"]
    %w[aspect-video w-full object-cover].each { |klass| assert_includes img["class"].split, klass }
    assert_not_includes img["class"].split, "rounded-2xl"
    assert_equal %w[h1 p section], kids[1].element_children.map(&:name)
    assert_includes kids[1]["class"].split, "p-3.5"
    section = kids[1].at_css("section")
    assert_includes section["class"].split, "border-t"
    assert_not_includes section["class"].split, "rounded-2xl"
    assert_equal 1, css_select("#product-purchase").size
    assert_equal 1, css_select("main img").size, "the cover isn't drawn a second time"
    assert_equal "#{FREE_LINE} 이용하기 E01은 로그인 없이 볼 수 있습니다.", box_text
    assert_includes kids[1].at_css("h1")["class"].split, "break-keep"
    html = css_select("main").first.to_html
    assert_operator html.index("data-guide-header"), :<, html.index("가이드 바로가기")
  end

  test "with an image, every state's box contents are as before (in use, closed, paid)" do
    [ @free, @paid ].each do |line|
      line.cover_image.attach(io: file_fixture("covers/cover.jpg").open, filename: "c.jpg", content_type: "image/jpeg")
      line.update!(cover_image_alt: "표지")
    end
    get product_line_path("paid-guide")
    assert css_select("[data-guide-cover]").any?
    assert_includes box_text, "1,100원 (VAT 포함)"
    sign_in(@member)
    post claim_free_access_path(@free.product.code)
    get product_line_path("free-guide")
    assert_equal "이용 중인 가이드입니다.", box_text
    @free.product.update!(sale_enabled: false)
    delete destroy_user_session_path
    get product_line_path("free-guide")
    assert_match(/\A현재 시작할 수 없습니다/, box_text)
  end

  test "with an image but no access box (no commerce product): the old layout -- name, summary, image" do
    plain = ProductLine.create!(internal_name: "pi", customer_name: "가격 없는 그림 가이드", slug: "plain-image", summary: "요약", introduction: "소개", status: "published")
    plain.content_episodes.create!(position: 1, customer_title: "편", body: "본문", status: "published")
    plain.cover_image.attach(io: file_fixture("covers/cover.jpg").open, filename: "c.jpg", content_type: "image/jpeg")
    plain.update!(cover_image_alt: "표지")
    get product_line_path("plain-image")
    assert_nil header
    assert_equal %w[h1 p div], css_select("main").first.element_children.first(3).map(&:name)
    assert_includes css_select("main > div.min-w-0 img").first["class"].split, "rounded-2xl"
  end

  test "a guide without a commerce product (no access box) is as before" do
    plain = ProductLine.create!(internal_name: "p", customer_name: "가격 없는 가이드", slug: "plain-guide", summary: "요약", introduction: "소개", status: "published")
    plain.content_episodes.create!(position: 1, customer_title: "편", body: "본문", status: "published")
    get product_line_path("plain-guide")
    assert_nil header
    assert_equal "h1", css_select("main").first.element_children.first.name
  end

  test "the admin preview never gets the header box (it always draws an image or the placeholder)" do
    sign_in(@admin)
    get admin_product_line_path(@free)
    assert_response :success
    assert_select "[data-guide-header]", 0
    assert_select "main h1", text: "가이드 free-guide 설치부터 내 프로젝트까지"
  end
end
