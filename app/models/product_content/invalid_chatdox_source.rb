class ProductContent::InvalidChatdoxSource
  def initialize(product_code)
    @product_code = product_code
  end

  def usable?
    false
  end

  def diagnostics
    [
      ProductContent::SeasonMetadata::Diagnostic.new(
        severity: :error,
        code: :invalid_chatdox_source_mode,
        location: "CHATDOX_CONTENT_SOURCE",
        message: "Configured Chatdox content source mode is invalid"
      )
    ]
  end

  def chapters = []
  def phases = []
  def licensed_chapter_ranges = []
  def guest_chapter_limit = 0
  def trial_chapter_limit = 0
  def find(_id) = nil
  def path = Rails.root.join("runtime/unavailable")
  def images_path = path.join("images")
  def missing_chapter_message = "콘텐츠 source 설정이 올바르지 않습니다."
  def editorial_status(_id) = :missing
  def last_updated_at(_slug) = nil
  def theme = { accent: "blue", label: "CHATDOX", back_link_label: "문서 목록", index_heading: "완전한 커리큘럼" }
end
