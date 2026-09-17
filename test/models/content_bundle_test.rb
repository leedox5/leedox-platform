require "test_helper"

# Handoff 0055 -- ContentBundle#slug validation/normalization.
class ContentBundleTest < ActiveSupport::TestCase
  setup do
    @product = Product.create!(code: "content_lab", name: "Content Lab", active: true)
  end

  test "a draft bundle not connected to any Product can be saved with no slug at all" do
    bundle = ContentBundle.new(internal_name: "연결 안 된 초안")
    assert bundle.valid?
    assert_nil bundle.slug
  end

  test "connecting a bundle to a Product without a slug is rejected with an understandable error" do
    bundle = ContentBundle.new(internal_name: "슬러그 없음", product: @product)
    assert_not bundle.valid?
    assert_includes bundle.errors[:slug].join, "slug"
  end

  test "slug is normalized to lowercase and trimmed" do
    bundle = ContentBundle.create!(internal_name: "정규화", product: @product, slug: "  Codex-TODO  ")
    assert_equal "codex-todo", bundle.slug
  end

  test "blank slug input normalizes to nil, not an empty string" do
    bundle = ContentBundle.new(internal_name: "빈값", slug: "   ")
    bundle.valid?
    assert_nil bundle.slug
  end

  test "invalid characters (underscore, uppercase-after-normalization mixed symbols, leading/trailing hyphen) are rejected" do
    [ "codex_todo", "-leading-hyphen", "trailing-hyphen-", "double--hyphen", "has space" ].each do |bad_slug|
      bundle = ContentBundle.new(internal_name: "형식 테스트", slug: bad_slug)
      assert_not bundle.valid?, "expected #{bad_slug.inspect} to be rejected"
    end
  end

  test "slug must be unique within the same Product, but the same slug is fine across different Products" do
    other_product = Product.create!(code: "content_lab_2", name: "Content Lab 2", active: true)
    ContentBundle.create!(internal_name: "첫 번째", product: @product, slug: "intro", status: "published")

    duplicate = ContentBundle.new(internal_name: "중복", product: @product, slug: "intro")
    assert_not duplicate.valid?

    same_slug_other_product = ContentBundle.new(internal_name: "다른 상품", product: other_product, slug: "intro")
    assert same_slug_other_product.valid?
  end

  test "publishing without a slug and without a Product is fine -- the slug requirement is tied to product_id, not status" do
    bundle = ContentBundle.new(internal_name: "무연결 게시", status: "published")
    assert bundle.valid?
  end
end
