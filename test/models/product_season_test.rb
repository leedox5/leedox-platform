require "test_helper"

class ProductSeasonTest < ActiveSupport::TestCase
  setup do
    @line = ProductLine.create!(internal_name: "A", customer_name: "A", slug: "line-a", problem: "p", expected_result: "e", target_audience: "t")
    @other_line = ProductLine.create!(internal_name: "B", customer_name: "B", slug: "line-b", problem: "p", expected_result: "e", target_audience: "t")
  end

  def build(overrides = {})
    @line.product_seasons.new({ internal_name: "S01 내부", season_code: "S01", slug: "s01" }.merge(overrides))
  end

  test "requires a product line, internal name, season code and slug" do
    season = ProductSeason.new
    assert_not season.valid?
    %i[product_line internal_name season_code slug].each { |attr| assert_includes season.errors.attribute_names, attr }
  end

  test "normalizes season_code to uppercase and slug to lowercase, and rejects bad formats" do
    season = build(season_code: "  s01 ", slug: "  S01-Final ")
    assert season.save
    assert_equal "S01", season.season_code
    assert_equal "s01-final", season.slug

    assert_not build(season_code: "S 02", slug: "s02").valid?
    assert_not build(season_code: "S02", slug: "bad slug!").valid?
  end

  test "season_code and slug are unique within a product line but reusable across lines" do
    build.save!

    dup_code = build(slug: "other")
    assert_not dup_code.valid?
    assert_includes dup_code.errors.attribute_names, :season_code

    dup_slug = build(season_code: "S02")
    assert_not dup_slug.valid?
    assert_includes dup_slug.errors.attribute_names, :slug

    assert @other_line.product_seasons.new(internal_name: "x", season_code: "S01", slug: "s01").save
  end

  test "DB unique indexes back the validations" do
    build.save!
    assert_raises(ActiveRecord::RecordNotUnique) { build(slug: "other").save!(validate: false) }
  end

  test "status defaults to draft, visibility to public; both validated" do
    season = build.tap(&:save!)
    assert_equal "draft", season.status
    assert_equal "public", season.visibility

    season.status = "bogus"
    assert_not season.valid?
    season.status = "archived"
    season.visibility = "secret"
    assert_not season.valid?
  end

  test "customer scopes: listed = published+public, reachable = published+(public|unlisted)" do
    listed = build(season_code: "S01", slug: "s01", status: "published", visibility: "public").tap(&:save!)
    unlisted = build(season_code: "S02", slug: "s02", status: "published", visibility: "unlisted").tap(&:save!)
    private_season = build(season_code: "S03", slug: "s03", status: "published", visibility: "private").tap(&:save!)
    draft = build(season_code: "S04", slug: "s04", status: "draft", visibility: "public").tap(&:save!)

    assert_equal [ listed ], @line.product_seasons.customer_listed.to_a
    assert_equal [ listed, unlisted ].sort_by(&:id), @line.product_seasons.customer_reachable.to_a.sort_by(&:id)
    assert_not_includes @line.product_seasons.customer_reachable, private_season
    assert_not_includes @line.product_seasons.customer_reachable, draft
  end

  test "display_title falls back to internal_name" do
    assert_equal "S01 내부", build.display_title
    assert_equal "고객 제목", build(customer_title: "고객 제목").display_title
  end

  test "cannot be destroyed while it still has episodes" do
    season = build.tap(&:save!)
    season.content_episodes.create!(position: 1, customer_title: "편")
    assert_not season.destroy
  end
end
