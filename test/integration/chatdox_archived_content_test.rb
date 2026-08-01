require "test_helper"
require_relative "../support/content_snapshot_fixture"

class ChatdoxArchivedContentTest < ActionDispatch::IntegrationTest
  include ContentSnapshotFixture

  setup do
    Commerce::CatalogBootstrap.call!
    @directory = Dir.mktmpdir
    base = Pathname.new(@directory)
    source = base.join("source")
    create_product_tree(source, s01_status: "archived", s02_status: "review")
    @snapshot = base.join("runtime")
    ContentSnapshot::Builder.new(source_root: source, source_commit: "d" * 40, target: @snapshot).build!
    @previous_snapshot = ENV["CHATDOX_SNAPSHOT_PATH"]
    ENV["CHATDOX_SNAPSHOT_PATH"] = @snapshot.to_s
  end

  teardown do
    @previous_snapshot ? ENV["CHATDOX_SNAPSHOT_PATH"] = @previous_snapshot : ENV.delete("CHATDOX_SNAPSHOT_PATH")
    FileUtils.remove_entry(@directory)
  end

  test "archived body and image require a license and never use public caching" do
    get chatdox_episode_path("s01", "01")
    assert_response :not_found

    user = User.create!(name: "Archived Reader", email: "archived-reader@example.com", password: "LocalFixture!2026")
    create_license(user)
    post user_session_path, params: { user: { email: user.email, password: "LocalFixture!2026" } }

    get chatdox_episode_path("s01", "01")
    assert_response :success
    assert_select "meta[name='robots'][content='noindex,nofollow']"
    assert_select "img[src='#{archived_chatdox_episode_image_path('s01', '01', 'used.png')}']"

    get archived_chatdox_episode_image_path("s01", "01", "used.png")
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  private

  def create_license(user)
    today = Time.zone.today
    License.create!(
      user:, product: Product.find_by!(code: "chatdox"), source: "legacy", status: "active",
      starts_on: today, last_usable_on: today + 30.days,
      access_ends_at: License::KST.local(*(today + 31.days).yield_self { |date| [ date.year, date.month, date.day ] })
    )
  end
end
