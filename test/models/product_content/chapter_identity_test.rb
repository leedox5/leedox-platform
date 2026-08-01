require "test_helper"

class ProductContent::ChapterIdentityTest < ActiveSupport::TestCase
  test "maps only exact legacy S01 ids and accepts their canonical ids" do
    assert_equal "S01E01", canonicalize("01")
    assert_equal "S01E20", canonicalize("20")
    assert_equal "S01E01", canonicalize("S01E01")

    %w[00 21 1 001 nonsense S01E21].each do |id|
      result = normalize(id)
      assert_not result.supported?, id
      assert_equal :unknown_chatdox_chapter, result.reason
    end
  end

  test "does not rewrite another product's identity" do
    result = ProductContent::ChapterIdentity.normalize(product_code: "claudox", chapter_id: "01")

    assert result.supported?
    assert_equal "01", result.canonical_id
    assert_equal [ "01" ], result.aliases
  end

  private

  def canonicalize(id)
    ProductContent::ChapterIdentity.canonicalize(product_code: "chatdox", chapter_id: id)
  end

  def normalize(id)
    ProductContent::ChapterIdentity.normalize(product_code: "chatdox", chapter_id: id)
  end
end
