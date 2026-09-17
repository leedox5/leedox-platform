require "test_helper"

# Handoff 0053 R3 follow-up -- reproduces production's actual current state
# (ProductContent.registry already has "content_lab" deployed, but its
# migration hasn't run there yet, and no Product row exists either) and
# proves the customer-facing route degrades to a safe 404, never a 500.
#
# The real table-absence can't be reproduced against this suite's already-
# migrated test database, so `ProductContent::DatabaseSource.tables_ready?`
# is stubbed to `false` for the duration of each test instead -- that's the
# exact condition the guard checks, so stubbing it is equivalent to actually
# dropping the tables, without touching the shared test schema other tests
# rely on.
class DatabaseSourceMissingTablesTest < ActionDispatch::IntegrationTest
  def with_tables_not_ready
    original = ProductContent::DatabaseSource.method(:tables_ready?)
    ProductContent::DatabaseSource.define_singleton_method(:tables_ready?) { false }
    yield
  ensure
    ProductContent::DatabaseSource.define_singleton_method(:tables_ready?, &original)
  end

  test "DatabaseSource itself never queries content_bundles/content_episodes when tables_ready? is false" do
    source = ProductContent::DatabaseSource.new("content_lab")

    with_tables_not_ready do
      assert_equal [], source.chapters
      assert_nil source.find("01")
      assert_equal [], source.takeaways("01")
      assert_equal :missing, source.editorial_status("01")
    end
  end

  test "matches production today: content_lab registered, no migration run, no Product row -- direct URL is a clean 404, not a 500" do
    assert_not Product.exists?(code: "content_lab"), "this test asserts the no-Product-row case; a Product for content_lab would test something else"

    with_tables_not_ready do
      get "/content/content_lab"
      assert_response :success # empty list, same as any product with zero content
      get "/content/content_lab/01"
      assert_response :not_found
      assert_match(/아직 공개되지 않은 콘텐츠입니다/, response.body)
    end
  end

  test "with a Product row present but tables still not ready, direct URL is still a clean 404" do
    product = Product.create!(code: "content_lab", name: "Content Lab", active: true)

    with_tables_not_ready do
      get "/content/content_lab"
      assert_response :success
      get "/content/content_lab/01"
      assert_response :not_found
    end
  ensure
    product&.destroy
  end
end
