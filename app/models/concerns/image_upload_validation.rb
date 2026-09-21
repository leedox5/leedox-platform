# Shared upload checks for every user-supplied image (handoff 0056 R5's cover
# image rules, extracted in handoff 0063 so inline content images use the very
# same ones): extension and detected content type must agree, then the bytes
# are actually decoded -- header size against the pixel cap first (cheap, before
# any pixel is decoded), then a full decode to catch truncated/corrupt files;
# animated files are refused (the variants are single-frame stills).
#
# The host model passes its own limits (they differ per use, and tests stub
# them), and includes this AFTER its `has_one_attached`.
module ImageUploadValidation
  extend ActiveSupport::Concern

  TYPES = {
    ".jpg" => %w[image/jpeg],
    ".jpeg" => %w[image/jpeg],
    ".png" => %w[image/png],
    ".webp" => %w[image/webp]
  }.freeze

  private

  # True when a new file was just attached (not merely already stored).
  def new_image_attached?(attachment_name)
    attachment_changes[attachment_name.to_s].present?
  end

  def validate_uploaded_image(attachment_name, max_bytes:, max_pixels:)
    blob = public_send(attachment_name).blob
    return if blob.nil?

    extension = File.extname(blob.filename.to_s).downcase
    unless TYPES.key?(extension)
      return errors.add(attachment_name, "허용되지 않는 형식입니다 (허용: JPEG, PNG, WebP — SVG·GIF 등은 사용할 수 없습니다).")
    end
    unless TYPES[extension].include?(blob.content_type)
      return errors.add(attachment_name, "파일 내용이 #{extension} 이미지와 맞지 않습니다.")
    end
    if blob.byte_size > max_bytes
      return errors.add(attachment_name, "파일이 너무 큽니다 (최대 #{ActiveSupport::NumberHelper.number_to_human_size(max_bytes)}).")
    end

    check_image_decodes(attachment_name, max_pixels: max_pixels)
  end

  def check_image_decodes(attachment_name, max_pixels:)
    require "vips"
    data = pending_image_bytes(attachment_name)
    return if data.nil?

    image = Vips::Image.new_from_buffer(data, "", fail_on: :truncated)
    pages = image.get_typeof("n-pages").zero? ? 1 : image.get("n-pages")
    return errors.add(attachment_name, "애니메이션 이미지는 사용할 수 없습니다.") if pages > 1

    if image.width * image.height > max_pixels
      return errors.add(attachment_name, "해상도가 너무 큽니다 (최대 #{(max_pixels / 1_000_000.0).round(1)}메가픽셀, 예: 4096×4096).")
    end

    image.avg # forces a full decode; raises on truncated or corrupt data
  rescue Vips::Error
    errors.add(attachment_name, "이미지를 읽을 수 없습니다 (손상되었거나 지원하지 않는 파일입니다).")
  end

  def pending_image_bytes(attachment_name)
    attachable = attachment_changes[attachment_name.to_s].attachable
    io = attachable.is_a?(Hash) ? attachable[:io] : attachable
    return nil unless io.respond_to?(:read)

    io.rewind if io.respond_to?(:rewind)
    data = io.read
    io.rewind if io.respond_to?(:rewind)
    data
  end
end
