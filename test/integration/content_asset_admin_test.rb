require "test_helper"

# Handoff 0056 R4 -- admin upload / replace / delete / download of files on
# ProductSeason episodes.
class ContentAssetAdminTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = User.create!(name: "관리자", email: "asset-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @user = User.create!(name: "일반유저", email: "asset-user-#{SecureRandom.hex(3)}@example.com", password: "password123")
    @line = ProductLine.create!(internal_name: "A", customer_name: "A", slug: "line-a", introduction: "소개")
    @season = @line.product_seasons.create!(internal_name: "S01", season_code: "S01", slug: "s01")
    @episode = @season.content_episodes.create!(position: 1, customer_title: "첫 편")
    @bundle = ContentBundle.create!(internal_name: "레거시")
    @bundle_episode = @bundle.content_episodes.create!(position: 1, customer_title: "레거시 편")
  end

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def upload_params(overrides = {})
    { content_asset: { title: "소스코드 ZIP", kind: "소스코드", description: "설명", position: 1,
                       file: fixture_file_upload("assets/sample.zip", "application/zip") }.merge(overrides) }
  end

  def create_asset(attrs = {})
    @episode.content_assets.create!({ title: "기존", kind: "소스코드", position: 1,
      file: { io: file_fixture("assets/sample.zip").open, filename: "sample.zip", content_type: "application/zip" } }.merge(attrs))
  end

  test "guests and non-admins cannot reach or use any asset URL" do
    asset = create_asset
    urls = [ new_admin_content_episode_content_asset_path(@episode), edit_admin_content_asset_path(asset), download_admin_content_asset_path(asset) ]

    urls.each { |url| get url; assert_redirected_to new_user_session_path }
    sign_in_as(@user)
    urls.each { |url| get url; assert_redirected_to root_path }

    assert_no_difference [ "ContentAsset.count", "ActiveStorage::Blob.count" ] do
      post admin_content_episode_content_assets_path(@episode), params: upload_params
      delete admin_content_asset_path(asset)
    end
    assert ContentAsset.exists?(asset.id)
  end

  test "the asset section shows on Season episodes only" do
    sign_in_as(@admin)
    get edit_admin_content_episode_path(@episode)
    assert_response :success
    assert_match(/첨부 산출물/, response.body)
    assert_select "a[href=?]", new_admin_content_episode_content_asset_path(@episode)

    get edit_admin_content_episode_path(@bundle_episode)
    assert_response :success
    assert_no_match(/첨부 산출물/, response.body)
  end

  test "the asset routes refuse legacy Bundle episodes outright" do
    sign_in_as(@admin)
    get new_admin_content_episode_content_asset_path(@bundle_episode)
    assert_response :not_found

    assert_no_difference [ "ContentAsset.count", "ActiveStorage::Blob.count" ] do
      post admin_content_episode_content_assets_path(@bundle_episode), params: upload_params
      assert_response :not_found
    end

    # a row that somehow exists on a bundle episode is still not manageable here
    stray = ContentAsset.new(content_episode: @bundle_episode, title: "x", kind: "k", position: 1,
      file: { io: file_fixture("assets/sample.zip").open, filename: "sample.zip", content_type: "application/zip" })
    stray.save!
    get edit_admin_content_asset_path(stray)
    assert_response :not_found
    get download_admin_content_asset_path(stray)
    assert_response :not_found
    delete admin_content_asset_path(stray)
    assert_response :not_found
    assert ContentAsset.exists?(stray.id)
  end

  test "upload, list, download, replace and delete a draft episode's file" do
    sign_in_as(@admin)
    assert_equal "draft", @episode.status

    get new_admin_content_episode_content_asset_path(@episode)
    assert_response :success
    assert_select "form[enctype='multipart/form-data']"
    assert_select "input[name='content_asset[position]'][value='1']"

    assert_difference [ "ContentAsset.count", "ActiveStorage::Blob.count" ], 1 do
      post admin_content_episode_content_assets_path(@episode), params: upload_params
    end
    assert_redirected_to edit_admin_content_episode_path(@episode)
    asset = ContentAsset.last
    assert_equal @episode, asset.content_episode

    follow_redirect!
    assert_match(/소스코드 ZIP/, response.body)
    assert_match(/sample\.zip/, response.body)
    assert_match(/소스코드/, response.body)
    assert_select "a[href=?]", download_admin_content_asset_path(asset)

    get download_admin_content_asset_path(asset)
    assert_response :success
    assert_match(/\Aattachment/, response.headers["Content-Disposition"])
    assert_equal file_fixture("assets/sample.zip").binread, response.body.b

    old_key = asset.file.blob.key
    perform_enqueued_jobs do
      patch admin_content_asset_path(asset), params: { content_asset: { title: "바뀐 제목", file: fixture_file_upload("assets/sample.war", "application/zip") } }
    end
    assert_redirected_to edit_admin_content_episode_path(@episode)
    asset.reload
    assert_equal "바뀐 제목", asset.title
    assert_equal "sample.war", asset.file.filename.to_s
    assert_not ActiveStorage::Blob.service.exist?(old_key)

    perform_enqueued_jobs do
      assert_difference [ "ContentAsset.count", "ActiveStorage::Blob.count" ], -1 do
        delete admin_content_asset_path(asset)
      end
    end
    assert_redirected_to edit_admin_content_episode_path(@episode)
    assert_match(/바뀐 제목.*sample\.war.*삭제했습니다/, flash[:notice])
  end

  test "the delete button carries a confirm naming the title, filename and irreversibility" do
    sign_in_as(@admin)
    asset = create_asset(title: "삭제 대상 제목")
    get edit_admin_content_episode_path(@episode)
    confirm = css_select("form[action='#{admin_content_asset_path(asset)}'] button").first["data-turbo-confirm"]
    assert_includes confirm, "삭제 대상 제목"
    assert_includes confirm, "sample.zip"
    assert_includes confirm, "되돌릴 수 없습니다"
  end

  test "rejected uploads show an error and store nothing" do
    sign_in_as(@admin)
    assert_no_difference [ "ContentAsset.count", "ActiveStorage::Blob.count" ] do
      post admin_content_episode_content_assets_path(@episode), params: upload_params(file: fixture_file_upload("assets/evil.html", "text/html"))
      assert_response :unprocessable_entity
      assert_match(/허용되지 않는 파일 형식/, response.body)
      post admin_content_episode_content_assets_path(@episode), params: upload_params(file: nil)
      assert_response :unprocessable_entity
      post admin_content_episode_content_assets_path(@episode), params: upload_params(title: "")
      assert_response :unprocessable_entity
    end
  end

  test "editing metadata with no new file keeps the file; duplicate position is refused" do
    sign_in_as(@admin)
    asset = create_asset
    second = create_asset(title: "둘째", position: 2)

    patch admin_content_asset_path(asset), params: { content_asset: { title: "제목만 변경", kind: "구현 스펙" } }
    assert_redirected_to edit_admin_content_episode_path(@episode)
    assert_equal "sample.zip", asset.reload.file.filename.to_s
    assert_equal "구현 스펙", asset.kind

    patch admin_content_asset_path(second), params: { content_asset: { position: 1 } }
    assert_response :unprocessable_entity
    assert_equal 2, second.reload.position
  end

  test "a blank file field on update never detaches the stored file" do
    sign_in_as(@admin)
    asset = create_asset
    patch admin_content_asset_path(asset), params: { content_asset: { title: "빈 파일 필드", file: "" } }
    assert asset.reload.file.attached?
    assert_equal "sample.zip", asset.file.filename.to_s
  end

  test "admin preview lists a draft episode's assets and their downloads" do
    sign_in_as(@admin)
    asset = create_asset(title: "미리보기 자료")
    get admin_content_episode_path(@episode)
    assert_response :success
    assert_match(/미리보기 자료/, response.body)
    assert_select "a[href=?]", download_admin_content_asset_path(asset)
  end

  test "deleting an episode from the admin UI removes its assets and files" do
    sign_in_as(@admin)
    asset = create_asset
    key = asset.file.blob.key
    perform_enqueued_jobs do
      assert_difference "ContentAsset.count", -1 do
        delete admin_content_episode_path(@episode)
      end
    end
    assert_not ActiveStorage::Blob.service.exist?(key)
  end
end
