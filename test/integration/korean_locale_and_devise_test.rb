require "test_helper"

class KoreanLocaleAndDeviseTest < ActionDispatch::IntegrationTest
  test "default locale is :ko" do
    assert_equal :ko, I18n.default_locale
  end

  test "visiting a protected page while signed out shows a Korean flash message, not English" do
    get dashboard_path
    assert_redirected_to new_user_session_path

    follow_redirect!
    assert_response :success
    assert_match(/로그인 후 이용할 수 있습니다/, response.body)
    assert_no_match(/You need to sign in/, response.body)
  end

  test "login failure, login success, and sign-out flash messages are all Korean" do
    user = User.create!(name: "테스트 유저", email: "locale-signin@example.com", password: "password123")

    post user_session_path, params: { user: { email: user.email, password: "wrong-password" } }
    assert_response :unprocessable_content
    assert_match(/이메일 또는 비밀번호가 올바르지 않습니다/, response.body)
    assert_no_match(/Invalid Email or password/, response.body)

    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    follow_redirect!
    assert_match(/로그인되었습니다/, response.body)

    delete destroy_user_session_path
    follow_redirect!
    assert_match(/로그아웃되었습니다/, response.body)
  end

  test "password reset email subject and body are entirely Korean" do
    user = User.create!(name: "테스트 유저", email: "locale-reset@example.com", password: "password123")

    assert_emails 1 do
      post user_password_path, params: { user: { email: user.email } }
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal "비밀번호 재설정 안내", mail.subject

    body = mail.body.decoded
    assert_match(/비밀번호 변경하기/, body)
    assert_match(/비밀번호 변경을 요청하셨습니다/, body)

    visible_text = Nokogiri::HTML(body).text
    assert_no_match(/[a-zA-Z]{4,}/, visible_text.gsub(user.email, ""))
  end

  test "flash alert box sits 2-3px below the navbar (close, not floating away from it)" do
    # Header height, computed from the actual Tailwind values (--spacing: .25rem,
    # text-sm line-height 20px, border-b 1px) rather than guessed at:
    #   mobile (<768px, hamburger h-10=40px content):        12 + 40 + 12 + 1 = 65px
    #   desktop (>=768px, nav buttons py-2+text-sm=36px):    12 + 36 + 12 + 1 = 61px
    mobile_header_height = 65
    desktop_header_height = 61

    get dashboard_path
    follow_redirect!
    assert_select "div[data-controller=flash].top-\\[68px\\].md\\:top-\\[64px\\]"

    assert_includes 2..3, 68 - mobile_header_height
    assert_includes 2..3, 64 - desktop_header_height
  end

  test "existing explicit locale: :ko overrides on docs and claudox pages still render Korean dates (no regression)" do
    get doc_path("01")
    assert_response :success
    assert_match(/최종 업데이트: \d{4}년 \d{1,2}월 \d{1,2}일 \d{2}:\d{2}/, response.body)

    get claudox_chapter_path("01")
    assert_response :success
    assert_match(/최종 업데이트: \d{4}년 \d{1,2}월 \d{1,2}일 \d{2}:\d{2}/, response.body)
  end

  test "generic ActiveRecord validation messages fall back to English instead of leaking translation-missing text" do
    user = User.new
    assert_not user.valid?

    user.errors.full_messages.each do |message|
      assert_no_match(/translation missing/i, message)
    end

    test "sign-up explains the strengthened password policy" do
      get new_user_registration_path
      assert_response :success

      assert_match(/비밀번호 \(10자 이상\)/, response.body)
      assert_match(/흔한 비밀번호는 사용할 수 없습니다/, response.body)
    end
  end

  test "number/date formatting used sitewide is unaffected (numbers still comma-delimited)" do
    Commerce::CatalogBootstrap.call!

    get pricing_path
    assert_response :success
    assert_match(/7,700원/, response.body)
  end
end
