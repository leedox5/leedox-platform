# Replaces Curriculum/Claudox as two separate, hand-rolled chapter-listing
# implementations with one interface that multiple product-specific sources
# can satisfy (see docs/internal/content_platform_design.md, section A).
#
# Every source class must respond to:
#   #chapters                 -> Array<Hash>  (id/slug/title/kind/available/product_code, id order)
#   #find(id)                 -> Hash | nil
#   #phases                   -> Array<Hash>  (key/label/title/description/range)
#   #licensed_chapter_ranges  -> Array<Range> (DocPolicy's paid-access ranges)
#   #guest_chapter_limit      -> Integer
#   #trial_chapter_limit      -> Integer
#   #images_path              -> Pathname
#   #path                     -> Pathname (content directory)
#   #last_updated_at(slug)    -> ActiveSupport::TimeWithZone
#   #missing_chapter_message  -> String (shown when #find returns nil)
#   #editorial_status(id)     -> Symbol, admin-only, shape may vary per source
#
# A product with no entry in the registry gets FilesystemSource automatically
# -- that's what makes "new product = content folder + Product row" true. Only
# Chatdox is registered, because it can't safely use FilesystemSource yet (see
# ProductContent::ChatdoxLegacySource).
class ProductContent
  CHATDOX_SOURCE_MODES = %w[legacy seasoned].freeze
  PACKAGED_CHATDOX_SOURCE_COMMIT = "d89cd90461a96fc1980611c3b1bf81ee3b1e7b14"

  def self.for(product_code)
    return chatdox_source.new(product_code) if product_code == "chatdox"

    registry.fetch(product_code, FilesystemSource).new(product_code)
  end

  def self.registry
    { "chatdox" => ChatdoxLegacySource }
  end

  def self.chatdox_source_mode
    ENV.fetch("CHATDOX_CONTENT_SOURCE") { Rails.env.production? ? "seasoned" : "legacy" }
  end

  def self.chatdox_snapshot_path
    Pathname.new(ENV.fetch("CHATDOX_SNAPSHOT_PATH", Rails.root.join("runtime/chatdox").to_s))
  end

  def self.chatdox_expected_source_commit
    ENV["CHATDOX_EXPECTED_SOURCE_COMMIT"].presence || (PACKAGED_CHATDOX_SOURCE_COMMIT if Rails.env.production?)
  end

  def self.chatdox_source
    case chatdox_source_mode
    when "legacy" then ChatdoxLegacySource
    when "seasoned" then ChatdoxSeasonedCompatibilityAdapter
    else InvalidChatdoxSource
    end
  end

  def self.seasoned_chatdox(snapshot_path: chatdox_snapshot_path)
    ChatdoxSeasonedSource.new("chatdox", snapshot_path:)
  end
end
