require "test_helper"
require "vips"

# Handoff 0056 R5 -- ProductLine cover image: validation, cleanup, variants.
class ProductLineCoverTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def upload(name, content_type = nil, filename: name)
    { io: file_fixture("covers/#{name}").open, filename: filename, content_type: content_type }
  end

  def build_line(cover: "cover.jpg", type: "image/jpeg", **attrs)
    attrs = { internal_name: "내부", customer_name: "제품", slug: "cover-line", introduction: "소개",
              cover_image_alt: "대표 이미지 설명" }.merge(attrs)
    line = ProductLine.new(attrs)
    line.cover_image.attach(upload(cover, type)) if cover
    line
  end

  def with_limit(method, value)
    original = ProductLine.method(method)
    ProductLine.define_singleton_method(method) { value }
    yield
  ensure
    ProductLine.define_singleton_method(method, original)
  end

  def image_upload(width, height, suffix, filename:, type:)
    data = Vips::Image.black(width, height).cast(:uchar).copy(interpretation: :b_w).write_to_buffer(suffix)
    { io: StringIO.new(data), filename: filename, content_type: type }
  end

  test "a product line without an image stays valid (existing products keep working) and alt is optional then" do
    line = build_line(cover: nil, cover_image_alt: nil)
    assert line.save, line.errors.full_messages.to_sentence
    assert_not line.cover_image.attached?
    assert_nil line.cover_dimensions
  end

  test "alt text is required whenever an image is attached" do
    line = build_line(cover_image_alt: "")
    assert_not line.valid?
    assert_includes line.errors.attribute_names, :cover_image_alt
    assert build_line(cover_image_alt: "설명").save
  end

  test "alt text is capped at 200 characters" do
    assert_not build_line(cover_image_alt: "가" * 201).valid?
    assert build_line(cover_image_alt: "가" * 200).valid?
  end

  test "accepts JPEG, PNG and WebP" do
    { "cover.jpg" => "image/jpeg", "cover.png" => "image/png", "cover.webp" => "image/webp" }.each_with_index do |(name, type), i|
      line = build_line(cover: name, type: type, slug: "cover-line-#{i}")
      assert line.valid?, "#{name}: #{line.errors.full_messages.to_sentence}"
    end
  end

  test "rejects SVG, GIF, PDF and HTML by extension" do
    { "evil.svg" => "image/svg+xml", "anim.gif" => "image/gif", "doc.pdf" => "application/pdf" }.each do |name, type|
      line = build_line(cover: name, type: type)
      assert_not line.valid?, "#{name} accepted"
      assert_match(/허용되지 않는 형식/, line.errors[:cover_image].join)
    end
  end

  test "rejects a file whose bytes don't match its extension, even with a lying declared type" do
    html = build_line(cover: "not_image.jpg", type: "image/jpeg")
    assert_not html.valid?
    assert_match(/내용이 .jpg 이미지와 맞지 않습니다/, html.errors[:cover_image].join)

    png_as_jpg = build_line(cover: "cover.png", type: "image/jpeg")
    png_as_jpg.cover_image.attach(io: file_fixture("covers/cover.png").open, filename: "renamed.jpg", content_type: "image/jpeg")
    assert_not png_as_jpg.valid?

    svg_as_png = build_line(cover: "evil.svg", type: "image/png")
    svg_as_png.cover_image.attach(io: file_fixture("covers/evil.svg").open, filename: "logo.png", content_type: "image/png")
    assert_not svg_as_png.valid?
  end

  test "rejects a corrupt / truncated image" do
    line = build_line(cover: "truncated.jpg")
    assert_not line.valid?
    assert_match(/읽을 수 없습니다/, line.errors[:cover_image].join)
  end

  test "rejects an animated WebP" do
    frames = Array.new(3) { |i| Vips::Image.black(64, 36).linear(1, i * 60).cast(:uchar).copy(interpretation: :b_w) }
    animated = Vips::Image.arrayjoin(frames, across: 1).copy
    animated.set_type(GObject::GINT_TYPE, "page-height", 36)
    data = animated.write_to_buffer(".webp")
    line = build_line(cover: nil)
    line.cover_image.attach(io: StringIO.new(data), filename: "anim.webp", content_type: "image/webp")
    assert_not line.valid?
    assert_match(/애니메이션/, line.errors[:cover_image].join)
  end

  test "file size boundary: exactly at the limit passes, one byte over fails" do
    size = file_fixture("covers/cover.jpg").size
    with_limit(:max_cover_bytes, size) { assert build_line.valid? }
    with_limit(:max_cover_bytes, size - 1) do
      line = build_line
      assert_not line.valid?
      assert_match(/너무 큽니다/, line.errors[:cover_image].join)
    end
  end

  test "pixel boundary: exactly at the limit passes, one pixel over fails (640x360)" do
    pixels = 640 * 360
    with_limit(:max_cover_pixels, pixels) { assert build_line.valid? }
    with_limit(:max_cover_pixels, pixels - 1) do
      line = build_line
      assert_not line.valid?
      assert_match(/해상도가 너무 큽니다/, line.errors[:cover_image].join)
    end
  end

  test "documented defaults: 5MB and 4096x4096" do
    assert_equal 5.megabytes, ProductLine.max_cover_bytes
    assert_equal 4096 * 4096, ProductLine.max_cover_pixels
  end

  test "an oversized-pixel image is rejected from its header, without needing the limit override" do
    line = build_line(cover: nil)
    line.cover_image.attach(**image_upload(4097, 4096, ".png", filename: "huge.png", type: "image/png"))
    assert_not line.valid?
    assert_match(/해상도가 너무 큽니다/, line.errors[:cover_image].join)
  end

  test "a rejected upload stores no blob and leaves an existing cover untouched" do
    line = build_line.tap(&:save!)
    blob_id = line.cover_image.blob.id

    assert_no_difference "ActiveStorage::Blob.count" do
      line.cover_image.attach(upload("evil.svg", "image/svg+xml"))
      assert_not line.save
    end
    assert_equal blob_id, ProductLine.find(line.id).cover_image.blob.id
  end

  test "updating other fields keeps the cover, and doesn't re-validate the stored file" do
    line = build_line.tap(&:save!)
    blob_id = line.cover_image.blob.id
    line.update!(customer_name: "바뀐 이름")
    assert_equal blob_id, line.reload.cover_image.blob.id
  end

  test "hero and thumb are 16:9 WebP stills, generated once and stored" do
    line = build_line.tap(&:save!)

    hero = line.cover_image.variant(:hero).processed
    thumb = line.cover_image.variant(:thumb).processed
    { hero => [ 1600, 900 ], thumb => [ 480, 270 ] }.each do |variant, (w, h)|
      blob = variant.image.blob
      assert_equal "image/webp", blob.content_type
      image = Vips::Image.new_from_buffer(blob.download, "")
      assert_equal [ w, h ], [ image.width, image.height ]
    end

    assert_no_difference "ActiveStorage::Blob.count" do
      line.cover_image.variant(:hero).processed
    end
  end

  test "a non-16:9 original is cropped to the variant ratio" do
    line = build_line(cover: "portrait.jpg").tap(&:save!)
    image = Vips::Image.new_from_buffer(line.cover_image.variant(:thumb).processed.image.blob.download, "")
    assert_equal [ 480, 270 ], [ image.width, image.height ]
  end

  test "variants carry no metadata from the original" do
    line = build_line.tap(&:save!)
    data = line.cover_image.variant(:hero).processed.image.blob.download
    assert_not_includes Vips::Image.new_from_buffer(data, "").get_fields, "exif-data"
  end

  test "cover_dimensions reports the original's resolution" do
    assert_equal [ 640, 360 ], build_line.tap(&:save!).cover_dimensions
  end

  test "replacing the cover purges the old blob, its variants and stored files" do
    line = build_line.tap(&:save!)
    line.cover_image.variant(:hero).processed
    old_blob = line.cover_image.blob
    old_key = old_blob.key
    variant_keys = ActiveStorage::VariantRecord.where(blob_id: old_blob.id).map { |r| r.image.blob.key }
    assert_equal 1, variant_keys.size

    perform_enqueued_jobs do
      line.update!(cover_image: upload("cover.png", "image/png"))
    end

    assert_equal "cover.png", line.reload.cover_image.filename.to_s
    assert_not ActiveStorage::Blob.exists?(old_blob.id)
    assert_not ActiveStorage::Blob.service.exist?(old_key)
    assert_equal 0, ActiveStorage::VariantRecord.where(blob_id: old_blob.id).count
    variant_keys.each { |key| assert_not ActiveStorage::Blob.service.exist?(key) }
  end

  test "purging the cover removes attachment, blob, variants and files" do
    line = build_line.tap(&:save!)
    line.cover_image.variant(:thumb).processed
    keys = ActiveStorage::Blob.pluck(:key)
    assert_equal 2, keys.size

    perform_enqueued_jobs { line.cover_image.purge }

    assert_equal 0, ActiveStorage::Blob.count
    assert_equal 0, ActiveStorage::Attachment.count
    keys.each { |key| assert_not ActiveStorage::Blob.service.exist?(key) }
  end

  test "destroy is still refused while episodes exist and the cover is kept" do
    line = build_line.tap(&:save!)
    line.content_episodes.create!(position: 1, customer_title: "편")
    assert_not line.destroy
    assert ProductLine.find(line.id).cover_image.attached?
  end
end
