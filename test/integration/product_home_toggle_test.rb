require "test_helper"
require Rails.root.join("db/migrate/20261004040000_add_show_on_home_to_products")

# Handoff 0078 -- the home switch for standalone (pre-series) products and the tagline field on the admin
# product edit page. Home only: /pricing, product pages and access are untouched.
class ProductHomeToggleTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "ph-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @member = User.create!(name: "회원", email: "ph-user-#{SecureRandom.hex(3)}@example.com", password: "password123")
    @chatdox = Product.find_by!(code: "chatdox")
  end

  def sign_in(user)
    delete destroy_user_session_path
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def home_codes
    get root_path
    css_select("section[aria-labelledby='track-ai'] [data-product-code]").map { |n| n["data-product-code"] }
  end

  def pricing_names
    get pricing_path
    css_select("main article h2").map { |n| n.text.strip }
  end

  def save(product, attrs)
    patch admin_commerce_product_path(product), params: { product: { name: product.name }.merge(attrs) }
  end

  # --- backfill / defaults -------------------------------------------------------

  test "the migration's backfill: standalone products on, a ProductLine's commerce product off" do
    line = ProductLine.create!(internal_name: "S", customer_name: "시리즈", slug: "toggle-line", introduction: "소개", status: "published")
    ActiveRecord::Base.connection.execute("UPDATE products SET show_on_home = FALSE")
    linked = Product.create!(code: "toggle_linked", name: "연결 상품")
    line.update!(product: linked)

    # The migration's own backfill statement, run as-is. (Not migrate(:down)/(:up) inside a test: dropping and
    # re-adding the column reorders it, and statements SQLite already prepared then write into the wrong columns
    # for every later test in the process.)
    ActiveRecord::Base.connection.execute(AddShowOnHomeToProducts::BACKFILL_SQL)

    Product.standalone.each { |product| assert product.show_on_home?, "#{product.code} should start on" }
    assert_not linked.reload.show_on_home?
  end

  test "a product created from now on starts off; the catalog bootstrap creates its products on" do
    assert_not Product.create!(code: "brand_new", name: "새 상품").show_on_home?
    assert Product.where(code: Commerce::CatalogBootstrap::PRODUCTS.keys).all?(&:show_on_home?)
  end

  test "re-running the catalog bootstrap never turns a product back on" do
    @chatdox.update!(show_on_home: false)
    Commerce::CatalogBootstrap.call!
    assert_not @chatdox.reload.show_on_home?
  end

  # --- home / pricing -----------------------------------------------------------------

  test "the home's AI row shows only the switched-on standalone products, in /pricing's order; /pricing keeps all" do
    all = home_codes
    assert_equal 4, all.size
    @chatdox.update!(show_on_home: false)
    assert_equal all - [ "chatdox" ], home_codes, "same order, chatdox left out"
    assert_includes pricing_names, "Chatdox", "/pricing still lists a product that's off the home"
    get "/chatdox"
    assert_response :success
  end

  test "with every standalone product off and no AI series, the AI row disappears entirely" do
    Product.standalone.update_all(show_on_home: false)
    get root_path
    assert_select "section[aria-labelledby='track-ai']", 0
    assert_equal 4, pricing_names.size
  end

  test "with every standalone product off, an AI series alone keeps the row" do
    Product.standalone.update_all(show_on_home: false)
    ProductLine.create!(internal_name: "AI", customer_name: "AI 시리즈", slug: "ai-only", introduction: "소개", status: "published", track: "ai")
    get root_path
    assert_select "section[aria-labelledby='track-ai']", 1
    assert_select "section[aria-labelledby='track-ai'] [data-product-code]", 0
  end

  test "a ProductLine's commerce product never shows as a standalone card, even if its flag were on" do
    line = ProductLine.create!(internal_name: "S", customer_name: "시리즈", slug: "flag-line", introduction: "소개", status: "published")
    linked = Product.create!(code: "flag_linked", name: "연결 상품", show_on_home: true)
    line.update!(product: linked)
    assert_not_includes home_codes, "flag_linked"
  end

  test "the list is the same for guests, members and admins" do
    @chatdox.update!(show_on_home: false)
    lists = [ nil, @member, @admin ].map do |viewer|
      viewer ? sign_in(viewer) : delete(destroy_user_session_path)
      home_codes
    end
    assert_equal 1, lists.uniq.size
  end

  test "the home loads the AI row's products in one products query, without Rails.cache" do
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql] =~ /FROM "products"/ && payload[:name] != "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get root_path }
    standalone = queries.grep(/show_on_home/)
    assert_equal 1, standalone.size, queries.inspect
  end

  test "the home still renders if the products can't be loaded (e.g. before the column exists)" do
    original = Product.method(:on_home)
    Product.define_singleton_method(:on_home) { raise ActiveRecord::StatementInvalid, "no such column: show_on_home" }
    get root_path
    assert_response :success
    assert_select "section[aria-labelledby='track-ai'] [data-product-code]", 0
  ensure
    Product.define_singleton_method(:on_home, original)
  end

  # --- admin -------------------------------------------------------------------------------

  test "only admins reach the product admin" do
    get edit_admin_commerce_product_path(@chatdox)
    assert_redirected_to new_user_session_path
    sign_in(@member)
    get edit_admin_commerce_product_path(@chatdox)
    assert_redirected_to root_path
    save(@chatdox, show_on_home: "0")
    assert @chatdox.reload.show_on_home?
  end

  test "the edit page has the home switch and tagline for a standalone product, and saving reads back" do
    sign_in(@admin)
    get edit_admin_commerce_product_path(@chatdox)
    assert_select "input[type=checkbox][name='product[show_on_home]'][checked]"
    assert_select "input[name='product[tagline]'][maxlength='100']"
    assert_includes response.body, "켜면 홈 'AI와 함께 만들기' 줄에 나옵니다. 가격 페이지와 상품 페이지에는 영향이 없습니다."
    assert_includes response.body, "홈 카드와 가격 페이지 카드에 제목 아래 한 줄로 나옵니다. 비워 두면 그 줄이 생략됩니다."

    save(@chatdox, show_on_home: "0", tagline: "  새 한 줄 설명  ")
    assert_redirected_to admin_commerce_products_path
    get edit_admin_commerce_product_path(@chatdox)
    assert_select "input[type=checkbox][name='product[show_on_home]'][checked]", 0
    assert_select "input[name='product[tagline]'][value=?]", "새 한 줄 설명"
    assert_equal [ false, "새 한 줄 설명" ], [ @chatdox.reload.show_on_home, @chatdox.tagline ]
  end

  test "saving the switch and tagline leaves prices untouched, and saving prices leaves them untouched" do
    sign_in(@admin)
    before = @chatdox.product_offers.order(:duration_months).pluck(:duration_months, :total_amount, :active)
    save(@chatdox, show_on_home: "0", tagline: "설명")
    assert_equal before, @chatdox.product_offers.order(:duration_months).pluck(:duration_months, :total_amount, :active)

    patch admin_commerce_product_path(@chatdox), params: { product: { name: @chatdox.name,
      offers_attributes: { "0" => { duration_months: "1", total_amount: "9900", discount_pct: "0", active: "1" } } } }
    assert_equal [ false, "설명" ], [ @chatdox.reload.show_on_home, @chatdox.tagline ], "a form without the fields keeps them"
    assert_equal 9900, @chatdox.product_offers.find_by(duration_months: 1).total_amount
  end

  test "a tagline over 100 characters is refused; blank is fine and clears the line" do
    sign_in(@admin)
    save(@chatdox, tagline: "가" * 101)
    assert_response :unprocessable_entity
    assert_includes css_select("body").text, "한 줄 설명은 100자까지 쓸 수 있습니다."
    assert_equal Commerce::CatalogBootstrap::PRODUCTS["chatdox"][:tagline], @chatdox.reload.tagline

    save(@chatdox, tagline: "가" * 100)
    assert_equal 100, @chatdox.reload.tagline.length

    save(@chatdox, tagline: "   ")
    assert_nil @chatdox.reload.tagline
    get root_path
    card = css_select("[data-product-code='chatdox']").first
    assert card
    assert_empty card.css("p.leading-relaxed"), "no tagline line on the home card"
  end

  test "a ProductLine's commerce product shows neither field, and the server ignores them for it" do
    line = ProductLine.create!(internal_name: "S", customer_name: "시리즈", slug: "admin-line", introduction: "소개", status: "published")
    linked = Product.create!(code: "admin_linked", name: "연결 상품")
    line.update!(product: linked)
    sign_in(@admin)
    get edit_admin_commerce_product_path(linked)
    assert_select "input[name='product[show_on_home]']", 0
    assert_select "input[name='product[tagline]']", 0
    save(linked, show_on_home: "1", tagline: "무시되어야 함")
    assert_equal [ false, nil ], [ linked.reload.show_on_home, linked.tagline ]
  end

  test "the admin product list marks each product 홈 표시 / 홈 숨김" do
    @chatdox.update!(show_on_home: false)
    sign_in(@admin)
    get admin_commerce_products_path
    flags = css_select("tbody tr").to_h { |tr| [ tr.at_css("td p").text.strip, tr.at_css("[data-home-flag]").text.strip ] }
    assert_equal "홈 숨김", flags["chatdox"]
    assert_equal "홈 표시", flags["claudox"]
  end
end
