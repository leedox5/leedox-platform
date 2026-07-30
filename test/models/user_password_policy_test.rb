require "test_helper"

class UserPasswordPolicyTest < ActiveSupport::TestCase
  test "password must be at least ten characters" do
    user = build_user(password: "shortpass")

    assert_not user.valid?
    assert user.errors.added?(:password, :too_short, count: 10)
  end

  test "common passwords are rejected case insensitively" do
    user = build_user(password: "Qwerty1234")

    assert_not user.valid?
    assert_includes user.errors[:base], "너무 흔한 비밀번호입니다. 다른 비밀번호를 입력해 주세요."
  end

  test "an existing weak password does not prevent unrelated updates" do
    user = build_user(password: "StrongPass!42")
    user.save!
    user.update_columns(encrypted_password: Devise::Encryptor.digest(User, "123456"))

    assert user.update(name: "새 이름")
  end

  private

  def build_user(password:)
    User.new(
      name: "테스트 유저",
      email: "password-policy-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password
    )
  end
end
