require "test_helper"

class ContentAssetTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    line = ProductLine.create!(internal_name: "A", customer_name: "A", slug: "line-a", introduction: "소개")
    @episode = line.content_episodes.create!(position: 1, customer_title: "편")
  end

  def upload(name, content_type = nil, filename: name)
    { io: file_fixture("assets/#{name}").open, filename: filename, content_type: content_type }
  end

  def with_max_size(bytes)
    original = ContentAsset.method(:max_file_size)
    ContentAsset.define_singleton_method(:max_file_size) { bytes }
    yield
  ensure
    ContentAsset.define_singleton_method(:max_file_size, original)
  end

  def build_asset(fixture = "sample.zip", content_type = "application/zip", **attrs)
    @episode.content_assets.new({ title: "소스코드 ZIP", kind: "소스코드", position: 1, file: upload(fixture, content_type) }.merge(attrs))
  end

  test "saves with title, kind, position and a file; description is optional" do
    asset = build_asset
    assert asset.save, asset.errors.full_messages.to_sentence
    assert asset.file.attached?
    assert_nil asset.description
  end

  test "title, kind and file are required" do
    asset = @episode.content_assets.new(position: 1)
    assert_not asset.valid?
    %i[title kind file].each { |attr| assert_includes asset.errors.attribute_names, attr }
  end

  test "position is unique within an episode but reusable in another episode" do
    build_asset.save!
    dup = build_asset(title: "다른 파일")
    assert_not dup.valid?
    assert_includes dup.errors.attribute_names, :position

    other_episode = @episode.product_line.content_episodes.create!(position: 2, customer_title: "다음 편")
    assert other_episode.content_assets.new(title: "x", kind: "k", position: 1, file: upload("sample.zip", "application/zip")).valid?
  end

  test "DB unique index backs position uniqueness" do
    build_asset.save!
    assert_raises(ActiveRecord::RecordNotUnique) { build_asset(title: "dup").save!(validate: false) }
  end

  test "accepts zip, war, markdown, text and pdf" do
    { "sample.zip" => "application/zip", "sample.war" => "application/zip", "sample.md" => "text/markdown",
      "sample.txt" => "text/plain", "sample.pdf" => "application/pdf" }.each_with_index do |(name, type), i|
      asset = build_asset(name, type, position: i + 1)
      assert asset.valid?, "#{name}: #{asset.errors.full_messages.to_sentence}"
    end
  end

  test "rejects html, svg, executables and scripts by extension" do
    %w[evil.html evil.svg evil.exe evil.sh].each do |name|
      asset = build_asset(name, "application/octet-stream")
      assert_not asset.valid?, "#{name} was accepted"
      assert_match(/허용되지 않는 파일 형식/, asset.errors[:file].join)
    end
  end

  test "rejects a file whose bytes don't match its extension, even with a lying declared type" do
    zip = build_asset("fake.zip", "application/zip")
    assert_not zip.valid?
    assert_match(/내용이 .zip 형식과 맞지 않습니다/, zip.errors[:file].join)

    txt = build_asset("fake_notes.txt", "text/plain", position: 2)
    assert_not txt.valid?
  end

  test "an allowed extension is required even when the content type is fine" do
    asset = build_asset("sample.zip", "application/zip", file: upload("sample.zip", "application/zip", filename: "sample.exe"))
    assert_not asset.valid?
  end

  test "size limit: exactly at the limit passes, one byte over fails" do
    size = file_fixture("assets/sample.zip").size
    with_max_size(size) { assert build_asset.valid? }
    with_max_size(size - 1) do
      asset = build_asset
      assert_not asset.valid?
      assert_match(/너무 큽니다/, asset.errors[:file].join)
    end
  end

  test "the default size limit is 100MB" do
    assert_equal 100.megabytes, ContentAsset.max_file_size
  end

  test "a failed validation stores no blob" do
    assert_no_difference "ActiveStorage::Blob.count" do
      build_asset("evil.html", "text/html").save
    end
  end

  test "replacing the file purges the old attachment and blob, keeps the row" do
    asset = build_asset.tap(&:save!)
    old_blob = asset.file.blob
    old_key = old_blob.key

    perform_enqueued_jobs do
      asset.update!(file: upload("sample.war", "application/zip"))
    end

    assert_equal "sample.war", asset.reload.file.filename.to_s
    assert_not ActiveStorage::Blob.exists?(old_blob.id)
    assert_not ActiveStorage::Blob.service.exist?(old_key)
    assert_equal 1, ActiveStorage::Attachment.where(record: asset).count
  end

  test "updating metadata without a new file keeps the stored file" do
    asset = build_asset.tap(&:save!)
    blob_id = asset.file.blob.id
    asset.update!(title: "바뀐 제목")
    assert_equal blob_id, asset.reload.file.blob.id
  end

  test "a rejected replacement leaves the original file in place" do
    asset = build_asset.tap(&:save!)
    blob_id = asset.file.blob.id
    assert_not asset.update(file: upload("evil.html", "text/html"))
    assert_equal blob_id, ContentAsset.find(asset.id).file.blob.id
  end

  test "destroying an asset removes its row, attachment, blob and stored file" do
    asset = build_asset.tap(&:save!)
    blob = asset.file.blob
    key = blob.key

    perform_enqueued_jobs { asset.destroy! }

    assert_not ContentAsset.exists?(asset.id)
    assert_equal 0, ActiveStorage::Attachment.where(blob_id: blob.id).count
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not ActiveStorage::Blob.service.exist?(key)
  end

  test "destroying an episode cascades to every asset, attachment, blob and stored file" do
    keys = [ build_asset.tap(&:save!), build_asset("sample.pdf", "application/pdf", position: 2, title: "스펙").tap(&:save!) ].map { |a| a.file.blob.key }

    assert_difference [ "ContentAsset.count", "ActiveStorage::Attachment.count" ], -2 do
      perform_enqueued_jobs { @episode.destroy! }
    end
    assert_equal 0, ActiveStorage::Blob.where(key: keys).count
    keys.each { |key| assert_not ActiveStorage::Blob.service.exist?(key) }
  end
end
