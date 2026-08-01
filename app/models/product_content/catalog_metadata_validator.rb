class ProductContent::CatalogMetadataValidator
  SCHEMA_VERSION = 1
  SEASON_CODE = /\As\d{2}\z/
  SAFE_BASENAME = /\A[a-z0-9][a-z0-9_-]*\z/

  def initialize(root:, expected_product_code:, raw:)
    @root = Pathname.new(root).expand_path
    @expected_product_code = expected_product_code
    @raw = raw
    @diagnostics = []
  end

  def call
    unless @raw.is_a?(Hash)
      error(:invalid_catalog_document, "root", "Catalog root must be a mapping")
      return result
    end

    validate_schema
    product = validate_product
    entries = validate_entries
    validate_duplicates(entries)
    seasons = load_seasons(entries)
    validate_unregistered_directories(entries)

    result(product:, seasons:)
  end

  private

  def validate_schema
    version = @raw["schema_version"]
    if version.nil?
      error(:missing_catalog_schema_version, "schema_version", "Catalog schema version is required; supported version is 1")
    elsif version != SCHEMA_VERSION
      error(:unsupported_catalog_schema_version, "schema_version", "Unsupported catalog schema version #{version.inspect}; supported version is 1")
    end
  end

  def validate_product
    value = @raw["product"]
    unless value.is_a?(Hash)
      error(:invalid_catalog_product, "product", "Product must be a mapping")
      return {}
    end

    code = value["code"]
    title = value["title"]
    error(:unexpected_product_code, "product.code", "Product code must be #{@expected_product_code}") unless code == @expected_product_code
    error(:missing_product_title, "product.title", "Product title is required") unless title.is_a?(String) && title.present?
    { code:, title: }
  end

  def validate_entries
    values = @raw["seasons"]
    unless values.is_a?(Array) && values.any?
      error(:invalid_season_collection, "seasons", "Seasons must be a non-empty list")
      return []
    end

    values.each_with_index.map do |value, index|
      location = "seasons[#{index}]"
      unless value.is_a?(Hash)
        error(:invalid_catalog_season, location, "Catalog season must be a mapping")
        next { index: }
      end

      code = value["code"]
      order = value["order"]
      path = value["path"]
      error(:invalid_catalog_season_code, "#{location}.code", "Season code must match sNN") unless code.is_a?(String) && SEASON_CODE.match?(code)
      error(:invalid_catalog_season_order, "#{location}.order", "Season order must be a positive integer") unless order.is_a?(Integer) && order.positive?
      unless path.is_a?(String) && SAFE_BASENAME.match?(path)
        error(:unsafe_catalog_season_path, "#{location}.path", "Season path must be a safe relative basename")
      end
      error(:catalog_code_path_mismatch, "#{location}.path", "Season path must match its code") if code.is_a?(String) && path.is_a?(String) && code != path
      { index:, code:, order:, path: }
    end
  end

  def validate_duplicates(entries)
    duplicate_values(entries, :code).each do |code|
      error(:duplicate_catalog_season_code, "seasons", "Season code #{code} is duplicated")
    end
    duplicate_values(entries, :order).each do |order|
      error(:duplicate_catalog_season_order, "seasons", "Season order #{order} is duplicated")
    end
    duplicate_values(entries, :path).each do |path|
      error(:duplicate_catalog_season_path, "seasons", "Season path #{path} is duplicated")
    end
  end

  def load_seasons(entries)
    entries.filter_map do |entry|
      next unless entry[:code].is_a?(String) && SEASON_CODE.match?(entry[:code])
      next unless entry[:path].is_a?(String) && SAFE_BASENAME.match?(entry[:path])

      path = @root.join(entry[:path])
      unless path.directory?
        error(:catalog_season_directory_missing, "seasons[#{entry[:index]}].path", "Registered season directory #{entry[:path]} is missing")
        next
      end
      unless contained_realpath?(path)
        error(:catalog_season_path_escape, "seasons[#{entry[:index]}].path", "Registered season directory resolves outside the product root")
        next
      end

      metadata = ProductContent::SeasonMetadataLoader.load(root: path, product_code: @expected_product_code)
      append_season_diagnostics(entry[:index], metadata.diagnostics)
      if metadata.season && metadata.season[:code] != entry[:code]
        error(:catalog_metadata_code_mismatch, "seasons[#{entry[:index]}].code", "Catalog and season metadata codes do not match")
      end
      if metadata.season && metadata.season[:order] != entry[:order]
        error(:catalog_metadata_order_mismatch, "seasons[#{entry[:index]}].order", "Catalog and season metadata orders do not match")
      end
      { code: entry[:code], order: entry[:order], path: entry[:path], metadata: }
    end.sort_by { |season| season[:order] || Float::INFINITY }
  end

  def validate_unregistered_directories(entries)
    registered = entries.filter_map { |entry| entry[:path] }.to_set
    @root.children.select(&:directory?).sort_by { |path| path.basename.to_s }.each do |path|
      name = path.basename.to_s
      next unless SEASON_CODE.match?(name)
      next if registered.include?(name)

      error(:unregistered_season_directory, name, "Season directory #{name} is not registered in the catalog")
    end
  rescue Errno::ENOENT
    nil
  end

  def append_season_diagnostics(index, diagnostics)
    diagnostics.each do |diagnostic|
      @diagnostics << ProductContent::SeasonMetadata::Diagnostic.new(
        severity: diagnostic.severity,
        code: diagnostic.code,
        location: "seasons[#{index}].metadata.#{diagnostic.location}",
        message: diagnostic.message
      )
    end
  end

  def contained_realpath?(path)
    root_realpath = @root.realpath
    candidate = path.realpath
    candidate == root_realpath || candidate.to_s.start_with?("#{root_realpath}#{File::SEPARATOR}")
  rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP
    false
  end

  def duplicate_values(entries, field)
    entries.filter_map { |entry| entry[field] }.tally.select { |_value, count| count > 1 }.keys.sort_by(&:to_s)
  end

  def error(code, location, message)
    @diagnostics << ProductContent::SeasonMetadata::Diagnostic.new(severity: :error, code:, location:, message:)
  end

  def result(product: nil, seasons: [])
    ProductContent::CatalogMetadata.new(product:, seasons:, diagnostics: @diagnostics)
  end
end
