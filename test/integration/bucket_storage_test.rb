require "test_helper"
require_relative "../support/fake_bucket"

# Handoff 0058 -- uploads, serving, deletion and failures with the S3-compatible
# bucket as the file storage (an in-memory FakeBucket driving the real
# Active Storage S3 service). The publish / license gates must behave exactly as
# they do on the Disk service, and no bucket URL may ever reach a browser.
class BucketStorageTest < ActionDispatch::IntegrationTest
  ENV_KEYS = %w[LEEDOX_COMMERCE_ENABLED].freeze

  setup do
    @previous_env = ENV_KEYS.to_h { |key| [ key, ENV[key] ] }
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    @bucket = FakeBucket.new
    @admin = User.create!(name: "관리자", email: "bucket-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @buyer = User.create!(name: "구매자", email: "bucket-buyer-#{SecureRandom.hex(3)}@example.com", password: "password123")
    @other = User.create!(name: "다른사람", email: "bucket-other-#{SecureRandom.hex(3)}@example.com", password: "password123")
  end

  teardown do
    @previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def sign_out
    delete destroy_user_session_path
  end

  def zip_upload(name = "sample.zip")
    fixture_file_upload("assets/#{name}", "application/zip")
  end

  # A published, license-gated Season with one published episode, a cover on
  # the product, and one file -- all stored in the fake bucket.
  def build_catalog
    @line = ProductLine.create!(internal_name: "A", customer_name: "제품", slug: "bucket-line", problem: "p", expected_result: "e", target_audience: "t", status: "published")
    @line.update!(cover_image: { io: file_fixture("covers/cover.jpg").open, filename: "cover.jpg", content_type: "image/jpeg" }, cover_image_alt: "대체문구")
    @season = @line.product_seasons.create!(internal_name: "S01", season_code: "S01", slug: "s01", status: "published", visibility: "public")
    @episode = @season.content_episodes.create!(position: 1, customer_title: "첫 편", body: "# 첫 편\n\n본문", status: "published")
    @asset = @episode.content_assets.create!(title: "소스", kind: "소스코드", position: 1,
      file: { io: file_fixture("assets/sample.zip").open, filename: "sample.zip", content_type: "application/zip" })
    Commerce::SeasonSales.set_price!(season: @season, total_amount: 33_000, actor: @admin)
    Commerce::SeasonSales.start_sale!(season: @season, actor: @admin)
    order = Commerce::OrderCreator.call!(user: @buyer, product_code: @season.reload.product.code, offer_code: @season.lifetime_offer.code, requested_start_on: nil, provider: "manual")
    Commerce::ConfirmManualPayment.call!(order: order, actor: @admin)
    @download = product_season_episode_asset_path(@line.slug, @season.slug, "01", @asset.id)
  end

  def with_bucket(&block)
    @bucket.install(&block)
  end

  # --- files really land in the bucket, not on disk ----------------------------

  test "uploads through the admin screens are stored in the bucket, and nothing touches the local disk" do
    with_bucket do
      @line = ProductLine.create!(internal_name: "A", customer_name: "제품", slug: "bucket-line", problem: "p", expected_result: "e", target_audience: "t")
      season = @line.product_seasons.create!(internal_name: "S01", season_code: "S01", slug: "s01")
      episode = season.content_episodes.create!(position: 1, customer_title: "편")
      sign_in(@admin)

      post admin_content_episode_content_assets_path(episode), params: { content_asset: { title: "소스", kind: "소스코드", position: 1, file: zip_upload } }
      assert_redirected_to edit_admin_content_episode_path(episode)
      asset = ContentAsset.last
      assert_equal "fake_bucket", asset.file.blob.service_name
      assert_equal [ asset.file.blob.key ], @bucket.keys
      assert_equal file_fixture("assets/sample.zip").binread, @bucket.objects[asset.file.blob.key]
      assert_not File.exist?(ActiveStorage::Service::DiskService.new(root: Rails.root.join("tmp/storage")).path_for(asset.file.blob.key))

      patch admin_product_line_path(@line), params: { product_line: { cover_image: fixture_file_upload("covers/cover.png", "image/png"), cover_image_alt: "대체" } }
      cover_blob = @line.reload.cover_image.blob
      assert_includes @bucket.keys, cover_blob.key
      assert_equal 2, @bucket.keys.size
    end
  end

  test "the stored file survives a 'new container': a fresh service object reads the same bytes and checksum" do
    with_bucket do
      build_catalog
      blob = @asset.file.blob
      reopened = ActiveStorage::Blob.find(blob.id)
      assert_equal Digest::MD5.base64digest(file_fixture("assets/sample.zip").binread), Digest::MD5.base64digest(reopened.download)
      assert_equal blob.checksum, Digest::MD5.base64digest(reopened.download)
    end
  end

  # --- access gates are unchanged --------------------------------------------

  test "downloads: owner gets the file as an attachment through the app; guests, non-owners and closed states are blocked" do
    with_bucket do
      build_catalog

      get @download
      assert_redirected_to new_user_session_path
      sign_in(@other)
      get @download
      assert_redirected_to product_season_path(@line.slug, @season.slug)
      sign_out

      sign_in(@buyer)
      get @download
      assert_response :success
      assert_equal file_fixture("assets/sample.zip").binread, response.body.b
      assert_match(/\Aattachment;/, response.headers["Content-Disposition"])
      assert_equal "private, no-store", response.headers["Cache-Control"]

      @episode.update!(status: "draft")
      get @download
      assert_response :not_found
      @episode.update!(status: "published")
      @season.update!(visibility: "private")
      get @download
      assert_response :not_found
      @season.update!(visibility: "public")
      @line.update!(status: "draft")
      get @download
      assert_response :not_found
      @line.update!(status: "published")

      get product_season_episode_asset_path(@line.slug, @season.slug, "01", 0)
      assert_response :not_found
    end
  end

  test "covers: published product serves the variant; draft and unpublished products are 404 even though the bucket has the file" do
    with_bucket do
      build_catalog
      get product_cover_path(@line.slug, "hero")
      assert_response :success
      assert_equal "image/webp", response.media_type
      assert(@bucket.keys.size >= 3, "original, variant and asset should all be in the bucket")

      %w[draft unpublished].each do |status|
        @line.update!(status: status)
        get product_cover_path(@line.slug, "hero")
        assert_response :not_found
      end
      get product_cover_path(@line.slug, "original")
      assert_response :not_found
    end
  end

  test "no bucket, endpoint or signed URL ever reaches a browser" do
    with_bucket do
      build_catalog
      sign_in(@buyer)
      pages = [ product_line_path(@line.slug), product_season_path(@line.slug, @season.slug), product_season_episode_path(@line.slug, @season.slug, "01") ]
      pages.each do |url|
        get url
        assert_no_match(/bucket\.invalid|fake-private-bucket|X-Amz|amazonaws|storage\.railway|active_storage|\/blobs\//, response.body)
      end
      [ @download, product_cover_path(@line.slug, "hero") ].each do |url|
        get url
        assert_response :success
        assert_nil response.headers["Location"]
        assert_no_match(/bucket\.invalid|X-Amz/, response.headers.to_h.values.join(" "))
      end
      # Active Storage's own routes remain switched off
      get "/rails/active_storage/blobs/redirect/#{@asset.file.blob.signed_id}/sample.zip"
      assert_response :not_found
    end
  end

  # --- deletion and replacement clean the bucket immediately ------------------

  test "replacing, deleting a file, deleting a cover and deleting an episode all remove the objects right away (no queued job needed)" do
    with_bucket do
      build_catalog
      sign_in(@admin)
      get product_cover_path(@line.slug, "hero") # creates the variant object

      old_key = @asset.file.blob.key
      patch admin_content_asset_path(@asset), params: { content_asset: { file: zip_upload("sample.war") } }
      assert_not @bucket.objects.key?(old_key), "replaced file must be deleted from the bucket"
      assert_includes @bucket.keys, @asset.reload.file.blob.key

      before = @bucket.keys.size
      delete admin_content_asset_path(@asset)
      assert_equal before - 1, @bucket.keys.size

      cover_keys = [ @line.cover_image.blob.key ] + ActiveStorage::VariantRecord.where(blob_id: @line.cover_image.blob.id).map { |v| v.image.blob.key }
      delete admin_product_line_cover_path(@line)
      cover_keys.each { |key| assert_not @bucket.objects.key?(key), "cover object #{key} left behind" }

      extra = @episode.content_assets.create!(title: "또", kind: "k", position: 5, file: { io: file_fixture("assets/sample.zip").open, filename: "sample.zip", content_type: "application/zip" })
      assert_includes @bucket.keys, extra.file.blob.key
      delete admin_content_episode_path(@episode)
      assert_empty @bucket.keys, "everything should be gone: #{@bucket.keys.inspect}"
    end
  end

  test "a failed bucket delete never breaks the request; the leftover is reported by the audit" do
    with_bucket do
      build_catalog
      sign_in(@admin)
      @bucket.fail_on(:delete_object, Aws::S3::Errors::ServiceUnavailable.new(nil, "down"))
      assert_nothing_raised { delete admin_content_asset_path(@asset) }
      assert_redirected_to edit_admin_content_episode_path(@episode)
      assert_not ContentAsset.exists?(@asset.id)

      @bucket.clear_failures
      audit = StorageVerifier.new(service: @bucket.service).audit
      assert_equal 1, audit.orphan_objects.size, "the object whose delete failed should show up as an orphan"
    end
  end

  # --- missing files and outages ---------------------------------------------

  test "a file missing from the bucket is a clean 404 for downloads and covers, never a 500 or a half-sent response" do
    with_bucket do
      build_catalog
      sign_in(@buyer)
      get product_cover_path(@line.slug, "hero")
      assert_response :success

      @bucket.objects.clear

      get @download
      assert_response :not_found
      assert_equal StorageFailures::MISSING_MESSAGE, response.body
      assert_nil response.headers["Content-Disposition"], "no attachment headers on a missing file"
      get product_cover_path(@line.slug, "hero")
      assert_response :not_found
      get product_cover_path(@line.slug, "thumb")
      assert_response :not_found
    end
  end

  test "a storage outage is a 503 with a retry hint and no provider details, for downloads, covers and the admin download" do
    with_bucket do
      build_catalog
      sign_in(@buyer)
      get product_cover_path(@line.slug, "hero")
      assert_response :success

      [ Aws::S3::Errors::ServiceUnavailable.new(nil, "secret-internal-detail"), Seahorse::Client::NetworkingError.new(Errno::ECONNREFUSED.new("secret-host")) ].each do |error|
        @bucket.outage = error
        get @download
        assert_response :service_unavailable
        assert_equal StorageFailures::UNAVAILABLE_MESSAGE, response.body
        assert_equal "30", response.headers["Retry-After"]
        assert_no_match(/secret/, response.body)

        get product_cover_path(@line.slug, "hero")
        assert_response :service_unavailable
        assert_equal "30", response.headers["Retry-After"]
      end

      @bucket.clear_failures
      sign_out
      sign_in(@admin)
      @bucket.outage = Aws::S3::Errors::ServiceUnavailable.new(nil, "down")
      get download_admin_content_asset_path(@asset)
      assert_response :service_unavailable
      @bucket.clear_failures
      get download_admin_content_asset_path(@asset)
      assert_response :success
    end
  end

  test "an outage during an admin upload shows a retry message and saves nothing; a failed replacement keeps the old file" do
    with_bucket do
      build_catalog
      sign_in(@admin)
      keys_before = @bucket.keys.sort
      counts_before = [ ContentAsset.count, ActiveStorage::Blob.count, ActiveStorage::Attachment.count ]
      @bucket.fail_on(:put_object, Aws::S3::Errors::ServiceUnavailable.new(nil, "down"))

      post admin_content_episode_content_assets_path(@episode), params: { content_asset: { title: "새 파일", kind: "k", position: 9, file: zip_upload("sample.war") } }
      assert_response :service_unavailable
      assert_includes response.body, StorageFailures::UNAVAILABLE_MESSAGE
      assert_equal counts_before, [ ContentAsset.count, ActiveStorage::Blob.count, ActiveStorage::Attachment.count ]

      old_blob_id = @asset.file.blob.id
      patch admin_content_asset_path(@asset), params: { content_asset: { title: "바뀐 제목", file: zip_upload("sample.war") } }
      assert_response :service_unavailable
      @asset.reload
      assert_equal old_blob_id, @asset.file.blob.id, "the record must still point at the old file"
      assert_equal "소스", @asset.title, "no partial save of the other fields"
      assert_equal keys_before, @bucket.keys.sort

      patch admin_product_line_path(@line), params: { product_line: { customer_name: "바뀐 이름", cover_image: fixture_file_upload("covers/cover.png", "image/png"), cover_image_alt: "새 대체" } }
      assert_response :service_unavailable
      assert_includes response.body, StorageFailures::UNAVAILABLE_MESSAGE
      assert_equal "제품", @line.reload.customer_name
      assert_equal "대체문구", @line.cover_image_alt
      assert_equal keys_before, @bucket.keys.sort

      post admin_product_lines_path, params: { product_line: { internal_name: "n", customer_name: "신규", slug: "new-line", problem: "p", expected_result: "e", target_audience: "t",
        cover_image: fixture_file_upload("covers/cover.jpg", "image/jpeg"), cover_image_alt: "설명" } }
      assert_response :service_unavailable
      assert_not ProductLine.exists?(slug: "new-line")

      @bucket.clear_failures
      post admin_content_episode_content_assets_path(@episode), params: { content_asset: { title: "새 파일", kind: "k", position: 9, file: zip_upload("sample.war") } }
      assert_redirected_to edit_admin_content_episode_path(@episode)
    end
  end

  # --- production must never accept uploads onto the container disk -------------

  test "with production rules on and the Disk service, uploads are refused with a clear message and nothing is saved" do
    previous = StoragePersistence.method(:enforced?)
    StoragePersistence.define_singleton_method(:enforced?) { true }
    line = ProductLine.create!(internal_name: "A", customer_name: "제품", slug: "guard-line", problem: "p", expected_result: "e", target_audience: "t")
    season = line.product_seasons.create!(internal_name: "S01", season_code: "S01", slug: "s01")
    episode = season.content_episodes.create!(position: 1, customer_title: "편")
    sign_in(@admin)

    assert_no_difference [ "ContentAsset.count", "ActiveStorage::Blob.count" ] do
      post admin_content_episode_content_assets_path(episode), params: { content_asset: { title: "소스", kind: "k", position: 1, file: zip_upload } }
      assert_response :unprocessable_entity
      assert_includes response.body, "영속 저장소"
    end
    assert_no_difference "ActiveStorage::Blob.count" do
      patch admin_product_line_path(line), params: { product_line: { cover_image: fixture_file_upload("covers/cover.jpg", "image/jpeg"), cover_image_alt: "설명" } }
      assert_response :unprocessable_entity
      assert_includes response.body, "영속 저장소"
    end

    @bucket.install do
      post admin_content_episode_content_assets_path(episode), params: { content_asset: { title: "소스", kind: "k", position: 1, file: zip_upload } }
      assert_redirected_to edit_admin_content_episode_path(episode)
      assert_equal 1, @bucket.keys.size
    end
  ensure
    StoragePersistence.define_singleton_method(:enforced?, previous)
  end

  test "outside production the Disk service still accepts uploads" do
    assert_not StoragePersistence.enforced?
    assert_not StoragePersistence.upload_blocked?
  end
end
