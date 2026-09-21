require "test_helper"

class ProductLineTest < ActiveSupport::TestCase
  def valid_attrs(overrides = {})
    {
      internal_name: "Codex TODO 내부명",
      customer_name: "Codex TODO",
      slug: "codex-todo",
      introduction: "제품 소개"
    }.merge(overrides)
  end

  test "saves with all required fields present" do
    product_line = ProductLine.new(valid_attrs)
    assert product_line.save
  end

  test "requires internal_name, customer_name and introduction" do
    product_line = ProductLine.new(valid_attrs(internal_name: "", customer_name: "", introduction: ""))
    assert_not product_line.save
    %i[internal_name customer_name introduction].each do |attr|
      assert_includes product_line.errors.attribute_names, attr
    end
  end

  test "ai_supporter is optional" do
    product_line = ProductLine.new(valid_attrs(ai_supporter: nil))
    assert product_line.save
  end

  test "normalizes slug to lowercase and requires kebab-case format" do
    product_line = ProductLine.new(valid_attrs(slug: "  Codex-TODO  "))
    assert product_line.save
    assert_equal "codex-todo", product_line.slug

    invalid = ProductLine.new(valid_attrs(slug: "Codex TODO!"))
    assert_not invalid.save
    assert_includes invalid.errors.attribute_names, :slug
  end

  test "slug must be unique across product lines" do
    ProductLine.create!(valid_attrs)
    dup = ProductLine.new(valid_attrs(internal_name: "다른 내부명"))
    assert_not dup.save
    assert_includes dup.errors.attribute_names, :slug
  end

  test "status defaults to draft and only accepts draft/published/unpublished" do
    product_line = ProductLine.create!(valid_attrs)
    assert_equal "draft", product_line.status
    assert_not product_line.published?

    product_line.status = "published"
    assert product_line.save
    assert_includes ProductLine.published, product_line

    product_line.status = "archived"
    assert_not product_line.valid?
    assert_includes product_line.errors.attribute_names, :status
  end

  test "restricts destroy while seasons still exist" do
    product_line = ProductLine.create!(valid_attrs)
    product_line.product_seasons.create!(internal_name: "S01", season_code: "S01", slug: "s01")

    assert_not product_line.destroy
    assert ProductLine.exists?(product_line.id)
  end

  test "has no relation to the commerce Product (that link is a later round)" do
    assert_not_includes ProductLine.reflect_on_all_associations.map(&:name), :products
    assert_not_includes Product.column_names, "product_line_id"
    assert_not_includes Product.column_names, "season_code"
  end
end
