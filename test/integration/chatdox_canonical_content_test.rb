require "test_helper"
require_relative "../support/content_snapshot_fixture"

class ChatdoxCanonicalContentTest < ActionDispatch::IntegrationTest
  include ContentSnapshotFixture

  COMMIT = "c" * 40

  setup do
    Commerce::CatalogBootstrap.call!
    @directory = Dir.mktmpdir
    base = Pathname.new(@directory)
    source = base.join("source")
    create_product_tree(source, s02_status: "review")
    metadata_path = source.join("s01/content_meta.yml")
    metadata = YAML.safe_load(metadata_path.read)
    metadata.fetch("episodes")[1]["status"] = "published"
    metadata.fetch("episodes") << episode("S01", 3, "published", "S01E03_trial")
    metadata.fetch("phases").first.fetch("episode_ids") << "S01E03"
    metadata_path.write(metadata.to_yaml)
    source.join("s01/S01E03_trial.md").write("# Trial Episode\n")
    @snapshot = base.join("runtime")
    ContentSnapshot::Builder.new(source_root: source, source_commit: COMMIT, target: @snapshot).build!
    @previous_snapshot = ENV["CHATDOX_SNAPSHOT_PATH"]
    ENV["CHATDOX_SNAPSHOT_PATH"] = @snapshot.to_s
  end

  teardown do
    @previous_snapshot ? ENV["CHATDOX_SNAPSHOT_PATH"] = @previous_snapshot : ENV.delete("CHATDOX_SNAPSHOT_PATH")
    FileUtils.remove_entry(@directory)
  end

  test "canonical season and episode routes are strict and do not collide with landing or legacy docs" do
    host! "localhost:3001"
    get chatdox_path
    assert_response :success

    get chatdox_season_path("s01")
    assert_response :success
    assert_match(/완료 0 \/ 공개 3/, response.body)

    get chatdox_episode_path("s01", "01")
    assert_response :success
    assert_match(/Episode 01/, response.body)
    assert_select "link[rel='canonical'][href='https://leedox.up.railway.app/chatdox/s01/01']"

    %w[/chatdox/S01 /chatdox/01 /chatdox/s01/1 /chatdox/s01/001 /chatdox/s99 /chatdox/s01/99].each do |path|
      get path
      assert_response :not_found, path
    end

    get doc_path("01")
    assert_response :success
  end

  test "upcoming season reveals no review or draft episode metadata" do
    get chatdox_season_path("s02")

    assert_response :success
    assert_match(/준비 중/, response.body)
    assert_match(/공개된 에피소드가 아직 없습니다/, response.body)
    assert_select "section[aria-label='공개 에피소드']"
    assert_no_match(/Episode 1|Episode 2|review|draft/i, response.body)

    get chatdox_episode_path("s02", "01")
    assert_response :not_found
  end

  test "canonical reader rewrites rendered public images but leaves fenced examples inert" do
    get chatdox_episode_path("s01", "01")

    assert_response :success
    assert_select "img[src='#{chatdox_season_image_path('s01', 'used.png')}']"
    assert_includes response.body, "/docs/images/example-only.png"
    assert_select "img[src*='example-only.png']", count: 0

    get chatdox_season_image_path("s01", "used.png")
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_match(/public.*immutable/, response.headers["Cache-Control"])

    get "/chatdox/s01/images/..%2Fcatalog.yml"
    assert_response :not_found
  end

  test "invalid snapshot returns generic 503 without diagnostics" do
    @snapshot.join("s01/S01E01_first.md").write("tampered")

    get chatdox_season_path("s01")

    assert_response :service_unavailable
    assert_equal "콘텐츠를 일시적으로 불러올 수 없습니다.", response.body
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_no_match(/checksum|#{Regexp.escape(@snapshot.to_s)}/i, response.body)
  end

  test "canonical completion writes canonical identity and cancel removes aliases" do
    user = create_user("canonical-reader@example.com")
    sign_in(user)

    post chapter_progresses_path, params: { product_code: "chatdox", chapter_id: "S01E01" }
    assert_redirected_to chatdox_episode_path("s01", "01")
    assert ChapterProgress.exists?(user:, product_code: "chatdox", chapter_id: "S01E01")

    ChapterProgress.insert!({
      user_id: user.id, product_code: "chatdox", chapter_id: "01", completed_at: Time.current,
      created_at: Time.current, updated_at: Time.current
    })
    delete chapter_progresses_path, params: { product_code: "chatdox", chapter_id: "S01E01" }
    assert_not ChapterProgress.exists?(user:, product_code: "chatdox", chapter_id: [ "01", "S01E01" ])
  end

  test "trial episode maps guest active trial expired trial and license states" do
    get chatdox_episode_path("s01", "03")
    assert_redirected_to new_user_session_path(redirect_to: "/chatdox/s01/03")

    active_trial = create_user("active-trial-reader@example.com")
    sign_in(active_trial)
    get chatdox_episode_path("s01", "03")
    assert_response :success

    delete destroy_user_session_path
    expired = create_user("expired-trial-reader@example.com")
    expired.update_columns(created_at: 8.days.ago)
    sign_in(expired)
    get chatdox_episode_path("s01", "03")
    assert_response :forbidden
    assert_match(/체험 기간이 종료되었습니다/, response.body)

    create_license(expired)
    get chatdox_episode_path("s01", "03")
    assert_response :success
  end

  test "login return path accepts canonical internal paths but rejects protocol-relative URLs" do
    user = create_user("safe-return-reader@example.com")

    get new_user_session_path(redirect_to: "//example.org/escape")
    sign_in(user)
    assert_redirected_to dashboard_path

    delete destroy_user_session_path
    get new_user_session_path(redirect_to: "/chatdox/s01/01")
    sign_in(user)
    assert_redirected_to "/chatdox/s01/01"
  end

  test "legacy reader publishes the new canonical URL" do
    get doc_path("01")

    assert_response :success
    assert_select "link[rel='canonical'][href='https://leedox.up.railway.app/chatdox/s01/01']"
  end

  private

  def create_user(email)
    User.create!(name: "Canonical Reader", email:, password: "LocalFixture!2026")
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "LocalFixture!2026" } }
  end

  def create_license(user)
    today = Time.zone.today
    end_date = today + 31.days
    License.create!(
      user:, product: Product.find_by!(code: "chatdox"), source: "legacy", status: "active",
      starts_on: today, last_usable_on: today + 30.days,
      access_ends_at: License::KST.local(end_date.year, end_date.month, end_date.day)
    )
  end
end
