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
  def self.for(product_code)
    registry.fetch(product_code, FilesystemSource).new(product_code)
  end

  def self.registry
    { "chatdox" => ChatdoxLegacySource }
  end
end
