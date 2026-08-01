class ProductContent::CatalogMetadata
  attr_reader :product, :seasons, :diagnostics

  def initialize(product:, seasons:, diagnostics:)
    @product = product&.freeze
    @seasons = seasons.map(&:freeze).freeze
    @diagnostics = diagnostics.freeze
  end

  def valid?
    diagnostics.none? { |diagnostic| diagnostic.severity == :error }
  end
end
