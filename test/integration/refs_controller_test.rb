require "test_helper"

# No prior coverage existed for this controller -- added while migrating it
# off Curriculum (necessary once Curriculum itself gets deleted, see stage 3
# result.md; RefsController is admin-only Chatdox payment reference docs,
# explicitly "not core" in the migration and left otherwise untouched).
class RefsControllerTest < ActionDispatch::IntegrationTest
  test "guests and non-admins are blocked, admins can browse and open a reference" do
    user = User.create!(name: "테스트 유저", email: "refs-user@example.com", password: "password123")
    admin = User.create!(name: "테스트 유저", email: "refs-admin@example.com", password: "password123", role: :admin)

    get refs_path
    assert_redirected_to root_path

    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    get refs_path
    assert_redirected_to root_path
    delete destroy_user_session_path

    post user_session_path, params: { user: { email: admin.email, password: "password123" } }
    get refs_path
    assert_response :success
    assert_match(/PortOne 결제 시스템/, response.body)

    get ref_path("payment-00_overview")
    assert_response :success
  end
end
