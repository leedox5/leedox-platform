require "test_helper"

# The WSL series' address changed in production (wsl -> wsl-core; its product code stays wsl). The old address and
# everything under it move permanently to the new one while the series is open to customers, and a series product's
# own-page link (the not-on-sale checkout's "가격 및 이용 기간 보기") always follows the series' current address --
# the stored landing_page_path kept the slug from when the sale first opened. Standalone products are unchanged.
class SeriesSlugRenameTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "sr-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
  end

  def wsl_line!(status: "published", visibility: "public")
    line = ProductLine.create!(internal_name: "wsl", customer_name: "WSL 실전 가이드", slug: "wsl-core", introduction: "소개",
      status: status, visibility: visibility)
    line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문", status: "published")
    line
  end

  # --- /products/wsl -> /products/wsl-core --------------------------------------------------------

  test "the old address and its episode and file paths move permanently to wsl-core" do
    wsl_line!
    get "/products/wsl"
    assert_response :moved_permanently
    assert_redirected_to "/products/wsl-core"

    get "/products/wsl/01"
    assert_response :moved_permanently
    assert_redirected_to "/products/wsl-core/01"

    get "/products/wsl/01/assets/7"
    assert_response :moved_permanently
    assert_redirected_to "/products/wsl-core/01/assets/7"

    follow_redirect!
    assert_response :not_found # an unknown file stays a 404 at its new address -- the move adds no gate of its own
  end

  test "the new address itself is untouched" do
    wsl_line!
    get "/products/wsl-core"
    assert_response :success
    get "/products/wsl-core/01"
    assert_response :success
  end

  test "a target customers can't open keeps the old 404 (no redirect that would reveal it)" do
    line = wsl_line!
    { "draft" => "public", "published" => "private" }.each do |status, visibility|
      line.update_columns(status: status, visibility: visibility)
      [ "/products/wsl", "/products/wsl/01" ].each do |path|
        get path
        assert_response :not_found, "#{status}/#{visibility} #{path}"
      end
    end
  end

  test "without a wsl-core series at all, /products/wsl is the plain 404" do
    get "/products/wsl"
    assert_response :not_found
  end

  # --- the checkout's own-page link ------------------------------------------------------------------

  test "a series whose slug changed: the not-on-sale checkout links to the current address" do
    line = ProductLine.create!(internal_name: "r", customer_name: "이름 바뀐 시리즈", slug: "old-name", introduction: "소개", status: "published")
    Commerce::ProductLineSales.set_price!(product_line: line, total_amount: 9_000, actor: @admin)
    product = line.reload.product
    assert_equal "/products/old-name", product.read_attribute(:landing_page_path), "stored when the sale first opened"

    line.update!(slug: "new-name")
    assert_not product.reload.sale_enabled?
    get billing_checkout_path(product.code)
    assert_response :success
    link = css_select("a").find { |a| a.text.include?("가격 및 이용 기간 보기") }
    assert_equal "/products/new-name#pricing", link["href"]
    assert_equal "/products/old-name", product.reload.read_attribute(:landing_page_path), "the stored value isn't rewritten"
  end

  test "a standalone product's link is unchanged" do
    Product.find_by!(code: "chatdox").update!(sale_enabled: false)
    get billing_checkout_path("chatdox")
    link = css_select("a").find { |a| a.text.include?("가격 및 이용 기간 보기") }
    assert_equal "/chatdox#pricing", link["href"]
    assert_equal "/chatdox", Product.find_by!(code: "chatdox").landing_page_path
  end
end
