require "test_helper"

# Handoff 0065 -- ProductSeason is a LEGACY record now (the Season layer is gone
# from the app; the table stays until the contract step). What is still true
# of it is only what the redirects and SeasonFlatten rely on.
class ProductSeasonTest < ActiveSupport::TestCase
  setup do
    @line = ProductLine.create!(internal_name: "A", customer_name: "A", slug: "line-a", introduction: "소개")
    @other_line = ProductLine.create!(internal_name: "B", customer_name: "B", slug: "line-b", introduction: "소개")
  end

  def build(overrides = {})
    ProductSeason.new({ product_line: @line, internal_name: "S01 내부", season_code: "S01", slug: "s01" }.merge(overrides))
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

    assert build(product_line: @other_line).save
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
end
