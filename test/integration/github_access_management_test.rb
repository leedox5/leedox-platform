require "test_helper"

class GithubAccessManagementTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @user = User.create!(name: "테스트 유저", email: "github-customer@example.com", password: "password123")
    @admin = User.create!(name: "테스트 유저", email: "github-admin@example.com", password: "password123", role: :admin)
  end

  test "user dashboard and admin dashboard do not expose GitHub Lab entry points in V1" do
    sign_in(@user)
    get dashboard_path
    assert_response :success
    assert_select "a[href=?]", github_access_path, count: 0
    assert_no_match(/Chatdox GitHub Lab/, response.body)

    delete destroy_user_session_path
    sign_in(@admin)
    get admin_dashboard_path
    assert_response :success
    assert_select "a[href=?]", admin_commerce_github_access_path, count: 0
    assert_no_match(/GitHub Lab 운영/, response.body)
  end

  test "direct URL access to user github_access is disabled in V1 and safely redirects" do
    sign_in(@user)

    get github_access_path
    assert_redirected_to dashboard_path
    assert_equal "GitHub Lab 연결 기능은 현재 V1 제공 범위에 포함되지 않습니다.", flash[:alert]

    post github_access_path, params: { external_account_link: { username: "octocat" } }
    assert_redirected_to dashboard_path
    assert_equal "GitHub Lab 연결 기능은 현재 V1 제공 범위에 포함되지 않습니다.", flash[:alert]
  end

  test "direct URL access to admin github_access GET, PATCH invite, and PATCH revoke are disabled in V1" do
    link = ExternalAccountLink.create!(user: @user, username: "lab-user")
    sign_in(@admin)

    get admin_commerce_github_access_path
    assert_redirected_to admin_dashboard_path
    assert_equal "GitHub Lab 운영 기능은 현재 V1 제공 범위에 포함되지 않습니다.", flash[:alert]

    patch admin_commerce_invite_github_access_path(link.public_id)
    assert_redirected_to admin_dashboard_path
    assert_equal "GitHub Lab 운영 기능은 현재 V1 제공 범위에 포함되지 않습니다.", flash[:alert]
    link.reload
    assert_nil link.invited_at, "invited_at should not be updated when invite route is disabled in V1"

    patch admin_commerce_revoke_github_access_path(link.public_id)
    assert_redirected_to admin_dashboard_path
    assert_equal "GitHub Lab 운영 기능은 현재 V1 제공 범위에 포함되지 않습니다.", flash[:alert]
    link.reload
    assert_nil link.revoked_at, "revoked_at should not be updated when revoke route is disabled in V1"
  end

  test "privacy policy states that GitHub account info is not collected in V1" do
    get privacy_path
    assert_response :success
    assert_match(/현재 V1 서비스에서는 GitHub 계정 및 저장소 연동 정보를 수집하지 않습니다/, response.body)
  end

  private

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
