require "test_helper"

class ProductContentTest < ActiveSupport::TestCase
  test "registered product codes get their registered source class" do
    assert_instance_of ProductContent::ChatdoxLegacySource, ProductContent.for("chatdox")
  end

  test "an unregistered product code automatically gets FilesystemSource -- this is what makes new-product registration code-free" do
    assert_instance_of ProductContent::FilesystemSource, ProductContent.for("claudox")
    assert_instance_of ProductContent::FilesystemSource, ProductContent.for("some_future_product_nobody_registered")
  end
end
