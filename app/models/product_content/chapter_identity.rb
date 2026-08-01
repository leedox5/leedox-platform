class ProductContent::ChapterIdentity
  Result = Data.define(:canonical_id, :aliases, :supported, :reason) do
    def supported? = supported
  end

  CHATDOX_S01_MAPPING = ProductContent::ChatdoxLegacySource::CHAPTERS.to_h do |chapter|
    [ chapter[:id], "S01E#{chapter[:id]}" ]
  end.freeze
  CHATDOX_CANONICAL_ID = /\AS\d{2}E\d{2}\z/

  def self.normalize(product_code:, chapter_id:, source: nil)
    id = chapter_id.to_s
    return passthrough(id) unless product_code == "chatdox"

    if (canonical = CHATDOX_S01_MAPPING[id])
      return Result.new(canonical_id: canonical, aliases: [ canonical, id ].freeze, supported: true, reason: :legacy_s01)
    end

    if CHATDOX_S01_MAPPING.value?(id)
      legacy = CHATDOX_S01_MAPPING.key(id)
      return Result.new(canonical_id: id, aliases: [ id, legacy ].freeze, supported: true, reason: :canonical_s01)
    end

    return known_canonical(id) if CHATDOX_CANONICAL_ID.match?(id) && known_to_source?(source, id)

    Result.new(canonical_id: nil, aliases: [ id ].freeze, supported: false, reason: :unknown_chatdox_chapter)
  end

  def self.canonicalize(**) = normalize(**).canonical_id

  def self.passthrough(id)
    Result.new(canonical_id: id, aliases: [ id ].freeze, supported: true, reason: :other_product)
  end
  private_class_method :passthrough

  def self.known_canonical(id)
    Result.new(canonical_id: id, aliases: [ id ].freeze, supported: true, reason: :canonical_source)
  end
  private_class_method :known_canonical

  def self.known_to_source?(source, id)
    return false unless source

    source.find(id).present? ||
      (source.respond_to?(:public_chapters) && source.public_chapters.any? { |chapter| chapter[:id] == id }) ||
      (source.respond_to?(:find_for_admin) && source.find_for_admin(id).present?)
  end
  private_class_method :known_to_source?
end
