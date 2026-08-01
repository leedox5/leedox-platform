require "test_helper"
require_relative "../support/content_snapshot_fixture"

class AdminChatdoxReadinessTest < ActionDispatch::IntegrationTest
  include ContentSnapshotFixture

  setup do
    @directory = Dir.mktmpdir
    @previous = %w[CHATDOX_CONTENT_SOURCE CHATDOX_SNAPSHOT_PATH CHATDOX_EXPECTED_SOURCE_COMMIT]
      .to_h { |key| [ key, ENV[key] ] }
  end

  teardown do
    @previous.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
    FileUtils.remove_entry(@directory)
  end

  test "readiness is admin-only and noindex" do
    user = User.create!(name: "Member", email: "readiness-member@example.com", password: "password123")
    sign_in(user)
    get admin_chatdox_readiness_path
    assert_redirected_to root_path

    sign_out
    admin = User.create!(name: "Admin", email: "readiness-admin@example.com", password: "password123", role: :admin)
    sign_in(admin)
    get admin_chatdox_readiness_path

    assert_response :success
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_select "meta[name=robots][content='noindex,nofollow']"
    assert_match(/not_configured/, response.body)
    assert_no_match(%r{/tmp/|CHATDOX_SNAPSHOT_PATH=}, response.body)
  end

  test "ready screen exposes only public season counts" do
    configure_snapshot
    admin = User.create!(name: "Admin", email: "ready-admin@example.com", password: "password123", role: :admin)
    sign_in(admin)

    get admin_chatdox_readiness_path

    assert_response :success
    assert_match(/ready/, response.body)
    assert_match(/s01.*completed.*1/m, response.body)
    assert_match(/s02.*upcoming.*0/m, response.body)
    assert_no_match(/Episode 2|draft|review/i, response.body)
  end

  private

  def configure_snapshot
    base = Pathname.new(@directory)
    source = base.join("source")
    create_product_tree(source, s02_status: "review")
    target = base.join("runtime")
    commit = "f" * 40
    ContentSnapshot::Builder.new(source_root: source, source_commit: commit, target:).build!
    ENV["CHATDOX_CONTENT_SOURCE"] = "seasoned"
    ENV["CHATDOX_SNAPSHOT_PATH"] = target.to_s
    ENV["CHATDOX_EXPECTED_SOURCE_COMMIT"] = commit
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def sign_out
    delete destroy_user_session_path
  end
end
