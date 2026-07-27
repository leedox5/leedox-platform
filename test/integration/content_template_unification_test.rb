require "test_helper"

# Regression coverage for leedox_content_template_unification_r1 --
# docs/*, claudox/*, and product_content/* are now a single shared template
# set (app/views/product_content/*), so these are the assertions that
# actually distinguish "unified but still looks/works right per product"
# from "accidentally flattened into one appearance."
class ContentTemplateUnificationTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
  end

  test "Chatdox reader pages render with the blue theme, unchanged" do
    get docs_path
    assert_response :success
    assert_match(/text-blue-600/, response.body)
    assert_no_match(/text-violet-600|bg-violet-50|text-emerald-600/, response.body)

    get doc_path("01")
    assert_response :success
    assert_match(/text-blue-600/, response.body)
    assert_no_match(/text-violet-600|bg-violet-50|text-emerald-600/, response.body)
    assert_select "aside", minimum: 1
  end

  test "Claudox reader pages render with the violet theme -- not blue, despite that being the reader's actual prior color" do
    get claudox_read_path
    assert_response :success
    assert_match(/text-violet-600/, response.body)

    get claudox_chapter_path("01")
    assert_response :success
    assert_match(/text-violet-600/, response.body)
    # No product-theme blue should remain inside the reader's own layout
    # (sidebar + main) -- the shared site header is out of scope here, it
    # isn't part of the product's own theme (e.g. its "회원가입" button).
    doc = Nokogiri::HTML(response.body)
    assert_empty doc.css("aside [class*='blue-600'], main [class*='blue-600']"),
      "expected no product-theme blue left inside the Claudox reader layout"
  end

  test "aistart renders with the emerald theme and now has a sidebar (backlog 014)" do
    get "/content/aistart"
    assert_response :success
    assert_match(/text-emerald-600/, response.body)

    get "/content/aistart/01"
    assert_response :success
    assert_match(/text-emerald-600/, response.body)
    assert_select "aside", minimum: 1
  end

  test "/content/aistart shows the real product name, not the product code titleized" do
    get "/content/aistart"
    assert_response :success
    assert_select "h1", text: /AI, 오늘부터 시작/
    assert_no_match(/Aistart/, response.body)
  end

  test "a chapter title never shows its own number twice" do
    get "/content/aistart"
    assert_response :success
    assert_no_match(/01\.\s*1\./, response.body)

    get claudox_read_path
    assert_response :success
    assert_no_match(/01\.\s*1\./, response.body)

    get docs_path
    assert_response :success
    assert_no_match(/01\.\s*1\./, response.body)
  end

  test "legacy URLs for both live products still work exactly as before: 200, correct content, same back-link target" do
    get docs_path
    assert_response :success
    assert_select "a[href=?]", doc_path("01"), minimum: 1

    get doc_path("01")
    assert_response :success
    assert_select "a[href=?]", docs_path, text: /문서 목록/

    get claudox_read_path
    assert_response :success
    assert_select "a[href=?]", claudox_chapter_path("01"), minimum: 1

    get claudox_chapter_path("01")
    assert_response :success
    assert_select "a[href=?]", claudox_read_path, text: /클로독스 목록/
  end

  test "docs/ and claudox/ dedicated view directories are gone" do
    assert_not Dir.exist?(Rails.root.join("app/views/docs"))
    assert_not Dir.exist?(Rails.root.join("app/views/claudox"))
  end
end
