require "test_helper"

# Handoff 0063 -- inline images of a ProductLine introduction / an Episode body.
class ContentImageTest < ActiveSupport::TestCase
  setup do
    @line = ProductLine.create!(internal_name: "A", customer_name: "제품", slug: "img-line", introduction: "소개", status: "published")
    @episode = @line.content_episodes.create!(position: 1, customer_title: "편", body: "본문", status: "published")
  end

  def upload(fixture = "covers/cover.jpg", type = "image/jpeg")
    { io: file_fixture(fixture).open, filename: File.basename(fixture), content_type: type }
  end

  def generated(width, height, suffix, filename:, type:)
    data = Vips::Image.black(width, height).cast(:uchar).copy(interpretation: :b_w).write_to_buffer(suffix)
    { io: StringIO.new(data), filename: filename, content_type: type }
  end

  def build(parent = @line, **attrs)
    parent.content_images.new({ alt: "설명", file: upload }.merge(attrs))
  end

  def with_class_method(klass, name, value)
    original = klass.method(name)
    klass.define_singleton_method(name) { value }
    yield
  ensure
    klass.define_singleton_method(name, original)
  end

  # --- basics ---------------------------------------------------------------

  test "saves for a product line or an episode, with a random public id and a growing position" do
    first = build.tap(&:save!)
    second = build.tap(&:save!)
    on_episode = build(@episode).tap(&:save!)

    assert_match(/\A[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/, first.public_id)
    assert_not_equal first.public_id, second.public_id
    assert_equal first.public_id, first.to_param
    assert_equal [ 0, 1 ], [ first.position, second.position ]
    assert_equal 0, on_episode.position
    assert_equal "image:#{first.public_id}", first.reference
    assert_equal "![설명](image:#{first.public_id})", first.markdown_snippet
  end

  test "alt text is required and bounded" do
    assert_not build(alt: "").valid?
    assert_includes build(alt: "").tap(&:valid?).errors[:alt].join, "대체문구"
    assert_not build(alt: "가" * (ContentImage::ALT_MAX_LENGTH + 1)).valid?
    assert build(alt: "가" * ContentImage::ALT_MAX_LENGTH).valid?
  end

  test "a file is required" do
    image = @line.content_images.new(alt: "설명")
    assert_not image.valid?
    assert image.errors[:file].any?
  end

  test "it belongs to exactly one parent, matching the database constraint" do
    both = ContentImage.new(alt: "x", product_line: @line, content_episode: @episode, file: upload)
    neither = ContentImage.new(alt: "x", file: upload)

    assert_not both.valid?
    assert_not neither.valid?
    assert_raises(ActiveRecord::StatementInvalid) do
      build.tap(&:save!).update_columns(content_episode_id: @episode.id) # now both parents set
    end
  end

  # --- upload validation (shared with the cover image) ----------------------

  test "only JPEG, PNG and WebP whose content matches are accepted" do
    assert build(file: upload("covers/cover.jpg", "image/jpeg")).valid?
    assert build(file: upload("covers/cover.png", "image/png")).valid?
    assert build(file: upload("covers/cover.webp", "image/webp")).valid?
    [ [ "covers/evil.svg", "image/svg+xml" ], [ "covers/anim.gif", "image/gif" ], [ "covers/doc.pdf", "application/pdf" ] ].each do |fixture, type|
      image = build(file: upload(fixture, type))
      assert_not image.valid?, "#{fixture} must be rejected"
      assert_includes image.errors[:file].join, "허용되지 않는 형식"
    end
    disguised = build(file: upload("covers/not_image.jpg", "image/jpeg"))
    assert_not disguised.valid?
    assert disguised.errors[:file].any?
  end

  test "a truncated or corrupt file is rejected" do
    image = build(file: upload("covers/truncated.jpg", "image/jpeg"))
    assert_not image.valid?
    assert image.errors[:file].any?
  end

  test "file size and pixel limits are enforced" do
    size = file_fixture("covers/cover.jpg").size
    with_class_method(ContentImage, :max_file_bytes, size) { assert build.valid? }
    with_class_method(ContentImage, :max_file_bytes, size - 1) do
      image = build
      assert_not image.valid?
      assert_includes image.errors[:file].join, "너무 큽니다"
    end
    with_class_method(ContentImage, :max_pixels, 100) do
      image = build(file: generated(20, 20, ".png", filename: "big.png", type: "image/png"))
      assert_not image.valid?
      assert_includes image.errors[:file].join, "해상도가 너무 큽니다"
    end
  end

  test "the production disk guard applies to inline images too" do
    with_class_method(StoragePersistence, :upload_blocked?, true) do
      image = build
      assert_not image.valid?
      assert_includes image.errors[:file].join, StoragePersistence::MESSAGE
    end
  end

  # --- per-record limits ----------------------------------------------------

  test "a record can hold only so many images" do
    with_class_method(ContentImage, :max_images_per_parent, 2) do
      2.times { build.save! }
      third = build
      assert_not third.valid?
      assert_includes third.errors[:base].join, "최대 2장"
      assert build(@episode).valid?, "the limit is per record, not global"
    end
  end

  test "a record can hold only so many bytes of images" do
    one = file_fixture("covers/cover.jpg").size
    with_class_method(ContentImage, :max_total_bytes_per_parent, one * 2 - 1) do
      build.save!
      image = build
      assert_not image.valid?
      assert_includes image.errors[:base].join, "총 용량"
    end
  end

  # --- variants keep the aspect ratio ----------------------------------------

  test "the body variant is a WebP no wider than 1600px and is never cropped" do
    wide = build(file: generated(2400, 600, ".png", filename: "wide.png", type: "image/png")).tap(&:save!)
    portrait = build(file: upload("covers/portrait.jpg", "image/jpeg")).tap(&:save!)

    wide_out = Vips::Image.new_from_buffer(wide.file.variant(:body).processed.image.blob.download, "")
    assert_equal 1600, wide_out.width
    assert_equal 400, wide_out.height, "2400x600 must stay 4:1 (no 16:9 crop)"
    assert_equal "image/webp", wide.file.variant(:body).processed.image.blob.content_type

    original = Vips::Image.new_from_buffer(portrait.file.download, "")
    out = Vips::Image.new_from_buffer(portrait.file.variant(:body).processed.image.blob.download, "")
    assert_in_delta original.width.to_f / original.height, out.width.to_f / out.height, 0.01
    assert_operator out.width, :<=, [ original.width, 1600 ].min

    thumb = Vips::Image.new_from_buffer(wide.file.variant(:thumb).processed.image.blob.download, "")
    assert_equal 480, thumb.width
  end

  # --- who may see it on a customer page ------------------------------------

  test "an introduction image is visible only while the product is published (admins always)" do
    image = build.tap(&:save!)
    guest = nil
    admin = User.create!(name: "관", email: "img-admin@example.com", password: "password123", role: :admin)

    assert image.visible_to?(guest)
    @line.update!(status: "draft")
    assert_not image.reload.visible_to?(guest)
    assert image.visible_to?(admin)
    assert_equal :short, image.cache_mode
  end

  test "an episode image follows the product and the episode gates" do
    image = build(@episode).tap(&:save!)
    assert image.visible_to?(nil)
    assert_equal :revalidate, image.cache_mode

    @episode.update!(status: "draft")
    assert_not image.reload.visible_to?(nil)
    @episode.update!(status: "published")

    @line.update!(visibility: "private")
    assert_not image.reload.visible_to?(nil)
    @line.update!(visibility: "unlisted")
    assert image.reload.visible_to?(nil), "an unlisted product is reachable by URL, so is its image"

    @line.update!(status: "unpublished")
    assert_not image.reload.visible_to?(nil)
    @line.update!(status: "draft")
    assert_not image.reload.visible_to?(nil)
  end

  test "an introduction image needs a reachable product, not just a published one" do
    image = build.tap(&:save!)
    @line.update!(visibility: "private")
    assert_not image.reload.visible_to?(nil)
    @line.update!(visibility: "public")
    assert image.reload.visible_to?(nil)
  end

  test "an episode image of a license-gated product needs an active license" do
    admin = User.create!(name: "관", email: "gate-admin@example.com", password: "password123", role: :admin)
    holder = User.create!(name: "보유", email: "gate-holder@example.com", password: "password123", created_at: 30.days.ago)
    other = User.create!(name: "타인", email: "gate-other@example.com", password: "password123", created_at: 30.days.ago)
    Commerce::CatalogBootstrap.call!
    Commerce::ProductLineSales.set_price!(product_line: @line, total_amount: 0, actor: admin)
    Commerce::ProductLineSales.start_sale!(product_line: @line, actor: admin)
    Commerce::ClaimFreeAccess.call!(user: holder, product_line: @line.reload)
    image = build(@episode).tap(&:save!)

    assert_not image.visible_to?(nil)
    assert_not image.visible_to?(other)
    assert image.visible_to?(holder)
    assert image.visible_to?(admin)
  end

  # --- referenced? and cleanup ----------------------------------------------

  test "it knows whether any text of its record still names it" do
    image = build(@episode).tap(&:save!)
    assert_not image.referenced?

    @episode.update!(body: "앞\n\n![x](#{image.reference})")
    assert image.reload.referenced?

    @episode.update!(body: "본문")
    @episode.content_takeaways.create!(kind: "카드", body: "![x](#{image.reference})", position: 1)
    assert image.reload.referenced?, "a takeaway of the same episode counts"

    intro_image = build.tap(&:save!)
    assert_not intro_image.referenced?
    @line.update!(introduction: "글 ![x](#{intro_image.reference})")
    assert intro_image.reload.referenced?
  end

  test "deleting the episode or the image removes the stored file too" do
    image = build(@episode).tap(&:save!)
    blob = image.file.blob
    assert ActiveStorage::Blob.exists?(blob.id)

    image.file.purge
    image.destroy!
    assert_not ActiveStorage::Blob.exists?(blob.id)

    second = build(@episode).tap(&:save!)
    assert_difference "ContentImage.count", -1 do
      @episode.destroy!
    end
    assert_not ContentImage.exists?(second.id)
  end
end
