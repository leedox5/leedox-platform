require "test_helper"
require_relative "../support/content_snapshot_fixture"

class ChatdoxLandingHubTest < ActionDispatch::IntegrationTest
  include ContentSnapshotFixture

  setup do
    Commerce::CatalogBootstrap.call!
    @directory = Dir.mktmpdir
    @previous_env = %w[CHATDOX_CONTENT_SOURCE CHATDOX_SNAPSHOT_PATH].to_h { |key| [ key, ENV[key] ] }
  end

  teardown do
    @previous_env.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
    FileUtils.remove_entry(@directory)
  end

  test "guest sees one product two seasons accurate release copy and no private S02 titles" do
    use_snapshot

    get chatdox_path

    assert_response :success
    assert_select "h1", text: "CHATDOX"
    assert_match(/실제 SaaS를 만들고.*운영하고.*성장시키는 기록/m, response.body)
    assert_match(/S01\. AI와 SaaS 구축하기/, response.body)
    assert_match(/S02\. SaaS에서 플랫폼으로/, response.body)
    assert_match(/기존 CHATDOX 라이선스로 두 시즌을 함께 이용/, response.body)
    assert_match(/공개된 에피소드가 아직 없습니다/, response.body)
    assert_no_match(/Episode 1|Episode 2|review|draft/i, response.body)
    assert_select "a[href=?]", chatdox_episode_path("s01", "01"), text: /첫 에피소드 읽기/
    assert_select "a[href=?]", chatdox_season_path("s02"), text: /S02 준비 이야기 보기/
    assert_select "a[href=?]", billing_checkout_path("s02"), count: 0
    assert_no_match(/완전한 커리큘럼 \(|기술 스택|20개 챕터/, response.body)
  end

  test "signed-in progress labels product-wide and season scopes separately" do
    use_snapshot
    user = User.create!(name: "Hub Partial", email: "hub-partial@example.com", password: "LocalFixture!2026")
    ChapterProgress.create!(user:, product_code: "chatdox", chapter_id: "S01E01", completed_at: Time.current)
    sign_in(user)

    get chatdox_path

    assert_response :success
    assert_match(/CHATDOX 전체 진도/, response.body)
    assert_match(/현재 공개된 모든 시즌 기준/, response.body)
    assert_match(/이 시즌 진도/, response.body)
    assert_match(/완료 1 \/ 공개 1/, response.body)
    assert_no_match(/0 \/ 공개 0.*%/m, response.body)
  end

  test "legacy mode keeps S01 readable and never activates an unsafe canonical S02 CTA" do
    ENV["CHATDOX_CONTENT_SOURCE"] = "legacy"
    ENV.delete("CHATDOX_SNAPSHOT_PATH")

    get chatdox_path

    assert_response :success
    assert_select "a[href=?]", doc_path("01"), minimum: 1
    assert_select "a[href=?]", chatdox_season_path("s02"), count: 0
    assert_match(/S02 공개 준비 중/, response.body)
  end

  test "unusable seasoned mode does not disguise itself as a legacy reading path" do
    ENV["CHATDOX_CONTENT_SOURCE"] = "seasoned"
    ENV["CHATDOX_SNAPSHOT_PATH"] = File.join(@directory, "missing")

    get chatdox_path

    assert_response :success
    assert_select "a[href=?]", doc_path("01"), count: 0
    assert_match(/콘텐츠 준비 중/, response.body)
    assert_match(/S02 공개 준비 중/, response.body)
  end

  test "first public S02 episode changes status and gives licensed completed S01 user the real next episode" do
    use_snapshot(s02_publishing: true)
    user = User.create!(name: "Hub Licensed", email: "hub-licensed@example.com", password: "LocalFixture!2026")
    ChapterProgress.create!(user:, product_code: "chatdox", chapter_id: "S01E01", completed_at: Time.current)
    create_license(user)
    sign_in(user)

    get chatdox_path

    assert_response :success
    s02 = Nokogiri::HTML(response.body).at_css("#season-s02")
    assert_match(/연재 중/, s02.text)
    assert_match(/공개 1편/, s02.text)
    assert s02.at_css("a[href='#{chatdox_episode_path('s02', '01')}']")
    assert_match(/완료 1 \/ 공개 2/, response.body)
    assert_match(/50%/, response.body)
  end

  private

  def use_snapshot(s02_publishing: false)
    base = Pathname.new(@directory)
    source = base.join("source")
    create_product_tree(source, s02_status: s02_publishing ? "published" : "review")
    if s02_publishing
      metadata_path = source.join("s02/content_meta.yml")
      metadata = YAML.safe_load(metadata_path.read)
      metadata.fetch("season")["status"] = "publishing"
      metadata_path.write(metadata.to_yaml)
    end
    target = base.join("runtime")
    ContentSnapshot::Builder.new(source_root: source, source_commit: "e" * 40, target:).build!
    ENV["CHATDOX_CONTENT_SOURCE"] = "seasoned"
    ENV["CHATDOX_SNAPSHOT_PATH"] = target.to_s
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
