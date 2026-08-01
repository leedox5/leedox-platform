class ProductContent::SeasonMetadata
  Diagnostic = Struct.new(:severity, :code, :location, :message, keyword_init: true) do
    def initialize(...)
      super
      freeze
    end

    def to_h
      { severity: severity, code: code, location: location, message: message }
    end
  end

  attr_reader :season, :phases, :chapters, :diagnostics, :images_path

  def initialize(season:, phases:, chapters:, diagnostics:, images_path:)
    @season = season&.freeze
    @phases = phases.map(&:freeze).freeze
    @chapters = chapters.map(&:freeze).freeze
    @diagnostics = diagnostics.freeze
    @images_path = images_path
  end

  def valid?
    diagnostics.none? { |diagnostic| diagnostic.severity == :error }
  end

  def public_chapters
    chapters.select { |chapter| chapter[:available] }
  end
end
