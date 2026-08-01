require "test_helper"

class ChatdoxPackagedContentTest < ActionDispatch::IntegrationTest
  APPROVED_COMMIT = "3efda2782671144e8aa3c6692f0fe1d91f6882d1"
  PRIVATE_S02_TITLES = [
    "안전장치가 바로 다음 작업에서 작동했다",
    "파일 오류가 접근 범위를 넓히지 않게 하기"
  ].freeze

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

  test "packaged S02 remains upcoming with no public or private episode disclosure" do
    [ chatdox_path, chatdox_season_path("s02") ].each do |path|
      get path

      assert_response :success
      assert_match(/준비 중/, response.body)
      assert_match(/공개(?:된 에피소드가 아직 없습니다| 0편)/, response.body)
      PRIVATE_S02_TITLES.each { |title| assert_no_match(/#{Regexp.escape(title)}/, response.body) }
      assert_no_match(/review|draft/i, response.body)
    end

    get chatdox_episode_path("s02", "01")
    assert_response :not_found
  end

  test "packaged artifact contains no S02 draft or review bodies" do
    snapshot = ProductContent::RuntimeSnapshotVerifier.verify(
      root: Rails.root.join("runtime/chatdox"), expected_source_commit: APPROVED_COMMIT
    )

    assert snapshot.usable?
    assert_equal 20, snapshot.manifest.fetch("seasons").find { |season| season["code"] == "s01" }.fetch("published_episode_count")
    assert_equal 0, snapshot.manifest.fetch("seasons").find { |season| season["code"] == "s02" }.fetch("published_episode_count")
    assert_empty Dir.glob(Rails.root.join("runtime/chatdox/s02/*.md"))
  end
end
