require "test_helper"

class ChatdoxPackagedContentTest < ActionDispatch::IntegrationTest
  APPROVED_COMMIT = "d89cd90461a96fc1980611c3b1bf81ee3b1e7b14"
  PUBLIC_S02_TITLE = "너는 ChatGPT인가, Codex인가"
  PRIVATE_S02_TITLE = "파일 오류가 접근 범위를 넓히지 않게 하기"

  setup do
    Commerce::CatalogBootstrap.call!
    @previous_env = %w[
      CHATDOX_CONTENT_SOURCE CHATDOX_SNAPSHOT_PATH CHATDOX_EXPECTED_SOURCE_COMMIT
    ].to_h { |key| [ key, ENV[key] ] }
    ENV["CHATDOX_CONTENT_SOURCE"] = "seasoned"
    ENV["CHATDOX_SNAPSHOT_PATH"] = Rails.root.join("runtime/chatdox").to_s
    ENV["CHATDOX_EXPECTED_SOURCE_COMMIT"] = APPROVED_COMMIT
  end

  teardown do
    @previous_env.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
  end

  test "packaged image content keeps public and compatibility routes available" do
    %w[/chatdox /chatdox/s01 /chatdox/s01/01 /chatdox/s02 /docs /docs/01].each do |path|
      get path
      assert_response :success, path
    end
  end

  test "packaged S02 publishes E01 to guests without disclosing E02" do
    [ chatdox_path, chatdox_season_path("s02") ].each do |path|
      get path

      assert_response :success
      assert_match(/연재 중/, response.body)
      assert_match(/공개 1편/, response.body)
      assert_no_match(/#{Regexp.escape(PRIVATE_S02_TITLE)}/, response.body)
      assert_no_match(/review|draft/i, response.body)
    end

    get chatdox_season_path("s02")
    assert_match(/#{Regexp.escape(PUBLIC_S02_TITLE)}/, response.body)

    get chatdox_episode_path("s02", "01")
    assert_response :success
    assert_select "h1", text: PUBLIC_S02_TITLE
    assert_match(/Codex/, response.body)

    get chatdox_episode_path("s02", "02")
    assert_response :not_found
  end

  test "packaged artifact contains only the published S02 body" do
    snapshot = ProductContent::RuntimeSnapshotVerifier.verify(
      root: Rails.root.join("runtime/chatdox"), expected_source_commit: APPROVED_COMMIT
    )

    assert snapshot.usable?
    assert_equal 20, snapshot.manifest.fetch("seasons").find { |season| season["code"] == "s01" }.fetch("published_episode_count")
    assert_equal 1, snapshot.manifest.fetch("seasons").find { |season| season["code"] == "s02" }.fetch("published_episode_count")
    assert_equal [ "S02E01_chatgpt_or_codex.md" ], Dir.glob(Rails.root.join("runtime/chatdox/s02/*.md")).map { |path| File.basename(path) }
    assert_equal 21, ProductContent::ChatdoxSeasonedSource.new.public_chapters.size
  end

  test "packaged contract records the approved commit and an env override can roll back" do
    assert_equal APPROVED_COMMIT, ProductContent::PACKAGED_CHATDOX_SOURCE_COMMIT
    ENV["CHATDOX_CONTENT_SOURCE"] = "legacy"
    assert_equal "legacy", ProductContent.chatdox_source_mode
  end
end
