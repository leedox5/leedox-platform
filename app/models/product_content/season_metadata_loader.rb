class ProductContent::SeasonMetadataLoader
  METADATA_FILENAME = "content_meta.yml"

  def self.load(root:, product_code: "chatdox")
    new(root:, product_code:).load
  end

  def initialize(root:, product_code:)
    @root = Pathname.new(root)
    @product_code = product_code.to_s
  end

  def load
    metadata_path = @root.join(METADATA_FILENAME)
    raw = YAML.safe_load(metadata_path.read, aliases: false)
    ProductContent::SeasonMetadataValidator.new(
      root: @root,
      product_code: @product_code,
      raw: raw
    ).call
  rescue Errno::ENOENT
    failure(:metadata_missing, METADATA_FILENAME, "Season metadata file is missing")
  rescue Psych::AliasesNotEnabled
    failure(:yaml_alias_forbidden, METADATA_FILENAME, "YAML aliases are not allowed")
  rescue Psych::DisallowedClass => error
    failure(:unsafe_yaml_object, METADATA_FILENAME, "YAML object type is not allowed: #{error.message.split.last}")
  rescue Psych::SyntaxError => error
    failure(:yaml_syntax_error, METADATA_FILENAME, "YAML syntax error at line #{error.line}")
  end

  private

  def failure(code, location, message)
    diagnostic = ProductContent::SeasonMetadata::Diagnostic.new(
      severity: :error,
      code:,
      location:,
      message:
    )
    ProductContent::SeasonMetadata.new(
      season: nil,
      phases: [],
      chapters: [],
      diagnostics: [ diagnostic ],
      images_path: nil
    )
  end
end
