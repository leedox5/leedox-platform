require "test_helper"
require_relative "../../support/content_snapshot_fixture"

class ProductContent::CatalogMetadataLoaderTest < ActiveSupport::TestCase
  include ContentSnapshotFixture

  test "loads and orders a valid S01 and S02 catalog" do
    with_product_tree do |root|
      result = load_catalog(root)

      assert result.valid?
      assert_equal "chatdox", result.product[:code]
      assert_equal %w[s01 s02], result.seasons.pluck(:code)
      assert result.seasons.all? { |season| season[:metadata].valid? }
      assert_equal %w[S01E01], result.seasons.first[:metadata].public_chapters.pluck(:id)
    end
  end

  test "rejects duplicate season code order and path" do
    {
      duplicate_catalog_season_code: [ "code", "s01" ],
      duplicate_catalog_season_order: [ "order", 1 ],
      duplicate_catalog_season_path: [ "path", "s01" ]
    }.each do |expected, (field, value)|
      with_product_tree do |root|
        catalog = read_catalog(root)
        catalog["seasons"][1][field] = value
        write_catalog(root, catalog)

        assert_includes load_catalog(root).diagnostics.pluck(:code), expected
      end
    end
  end

  test "rejects metadata code and order mismatches" do
    with_product_tree do |root|
      metadata = YAML.safe_load(root.join("s02/content_meta.yml").read)
      metadata["season"]["order"] = 3
      root.join("s02/content_meta.yml").write(metadata.to_yaml)

      assert_includes load_catalog(root).diagnostics.pluck(:code), :catalog_metadata_order_mismatch
    end
  end

  test "rejects missing and unregistered season directories" do
    with_product_tree do |root|
      root.join("s02").rmtree
      assert_includes load_catalog(root).diagnostics.pluck(:code), :catalog_season_directory_missing
    end

    with_product_tree do |root|
      root.join("s03").mkpath
      assert_includes load_catalog(root).diagnostics.pluck(:code), :unregistered_season_directory
    end
  end

  test "rejects unsafe catalog paths and symlink escapes" do
    with_product_tree do |root|
      catalog = read_catalog(root)
      catalog["seasons"][1]["path"] = "../s02"
      write_catalog(root, catalog)
      assert_includes load_catalog(root).diagnostics.pluck(:code), :unsafe_catalog_season_path
    end

    Dir.mktmpdir do |outside|
      with_product_tree do |root|
        root.join("s02").rmtree
        File.symlink(outside, root.join("s02"))
        assert_includes load_catalog(root).diagnostics.pluck(:code), :catalog_season_path_escape
      end
    end
  end

  test "rejects bad schema product code and YAML aliases" do
    with_product_tree do |root|
      catalog = read_catalog(root)
      catalog["schema_version"] = 2
      catalog["product"]["code"] = "other"
      write_catalog(root, catalog)
      codes = load_catalog(root).diagnostics.pluck(:code)

      assert_includes codes, :unsupported_catalog_schema_version
      assert_includes codes, :unexpected_product_code
    end

    with_product_tree do |root|
      root.join("catalog.yml").write("schema_version: 1\nproduct: &product { code: chatdox }\ncopy: *product\n")
      assert_includes load_catalog(root).diagnostics.pluck(:code), :catalog_yaml_alias_forbidden
    end
  end

  test "propagates season diagnostics and invalidates the catalog" do
    with_product_tree do |root|
      root.join("s02/S02E01_first.md").delete
      result = load_catalog(root)

      assert_not result.valid?
      diagnostic = result.diagnostics.find { |item| item.code == :published_body_missing }
      assert_equal "seasons[1].metadata.episodes[0].slug", diagnostic.location
    end
  end

  test "diagnostic order is deterministic" do
    with_product_tree do |root|
      root.join("s02").rmtree
      root.join("s03").mkpath

      first = load_catalog(root).diagnostics.map(&:to_h)
      second = load_catalog(root).diagnostics.map(&:to_h)
      assert_equal first, second
    end
  end

  private

  def with_product_tree
    Dir.mktmpdir do |directory|
      root = Pathname.new(directory).join("chatdox")
      create_product_tree(root)
      yield root
    end
  end

  def load_catalog(root)
    ProductContent::CatalogMetadataLoader.load(root:)
  end

  def read_catalog(root)
    YAML.safe_load(root.join("catalog.yml").read)
  end

  def write_catalog(root, catalog)
    root.join("catalog.yml").write(catalog.to_yaml)
  end
end
