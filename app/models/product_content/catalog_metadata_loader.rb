class ProductContent::CatalogMetadataLoader
  CATALOG_FILENAME = "catalog.yml"

  def self.load(root:, expected_product_code: "chatdox")
    new(root:, expected_product_code:).load
  end

  def initialize(root:, expected_product_code:)
    @root = Pathname.new(root)
    @expected_product_code = expected_product_code.to_s
  end

  def load
    raw = YAML.safe_load(@root.join(CATALOG_FILENAME).read, aliases: false)
    ProductContent::CatalogMetadataValidator.new(
      root: @root,
      expected_product_code: @expected_product_code,
      raw:
    ).call
  rescue Errno::ENOENT
    failure(:catalog_missing, CATALOG_FILENAME, "Product catalog file is missing")
  rescue Psych::AliasesNotEnabled
    failure(:catalog_yaml_alias_forbidden, CATALOG_FILENAME, "YAML aliases are not allowed")
  rescue Psych::DisallowedClass => error
    failure(:catalog_unsafe_yaml_object, CATALOG_FILENAME, "YAML object type is not allowed: #{error.message.split.last}")
  rescue Psych::SyntaxError => error
    failure(:catalog_yaml_syntax_error, CATALOG_FILENAME, "YAML syntax error at line #{error.line}")
  end

  private

  def failure(code, location, message)
    ProductContent::CatalogMetadata.new(
      product: nil,
      seasons: [],
      diagnostics: [ diagnostic(code, location, message) ]
    )
  end

  def diagnostic(code, location, message)
    ProductContent::SeasonMetadata::Diagnostic.new(severity: :error, code:, location:, message:)
  end
end
