require "test_helper"

class ProductTest < ActiveSupport::TestCase
  setup do
    Commerce::CatalogBootstrap.call!
  end

  test "returns correct signature theme accent string for all platform products" do
    assert_equal "emerald", Product.find_by!(code: "aigravity").theme
    assert_equal "violet", Product.find_by!(code: "claudox").theme
    assert_equal "blue", Product.find_by!(code: "chatdox").theme
    assert_equal "teal", Product.find_by!(code: "aistart").theme
  end

  test "returns correct catalog display_order for all platform products" do
    assert_equal 1, Product.find_by!(code: "aistart").display_order
    assert_equal 2, Product.find_by!(code: "chatdox").display_order
    assert_equal 3, Product.find_by!(code: "claudox").display_order
    assert_equal 4, Product.find_by!(code: "aigravity").display_order
  end

  test "correctly identifies free introductory gateway products" do
    assert Product.find_by!(code: "aistart").gateway?
    assert_not Product.find_by!(code: "chatdox").gateway?
    assert_not Product.find_by!(code: "claudox").gateway?
    assert_not Product.find_by!(code: "aigravity").gateway?
  end

  test "falls back safely for unknown custom product codes" do
    custom = Product.new(code: "custom_product", name: "Custom")
    assert_equal "blue", custom.theme
    assert_equal 99, custom.display_order
    assert_not custom.gateway?
  end
end
