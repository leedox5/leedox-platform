require "test_helper"

class DocsBackToListLinkTest < ActionDispatch::IntegrationTest
  test "the '문서 목록' link lives in <main>, not inside the sidebar that's hidden below md" do
    get doc_path("01")
    assert_response :success

    doc = Nokogiri::HTML(response.body)

    aside_link = doc.at_css("aside a[href='#{docs_path}']")
    assert_nil aside_link, "the back-to-list link must not be inside <aside> (hidden md:block -- invisible on mobile)"

    main_links = doc.css("main a[href='#{docs_path}']")
    assert_equal 1, main_links.size, "expected exactly one back-to-list link, in <main>"
    assert_equal "← 문서 목록", main_links.first.text.strip
  end

  test "the link still works: following it lands back on the doc list" do
    get doc_path("01")
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    link = doc.at_css("main a", text: "← 문서 목록")
    assert_equal docs_path, link["href"]

    get link["href"]
    assert_response :success
  end
end
