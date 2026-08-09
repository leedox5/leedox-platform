class User < ApplicationRecord
  COMMON_PASSWORDS = %w[
    0000000000
    1111111111
    1q2w3e4r5t
    1234567890
    abcdefghij
    adminadmin
    asdfghjkl
    computer123
    dragon12345
    football123
    iloveyou123
    letmein1234
    monkey12345
    password12
    princess123
    qazwsxedc
    qwerty1234
    qwertyuiop
    sunshine123
    superman123
    welcome123
    zxcvbnm123
  ].freeze

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :chapter_progresses, dependent: :destroy
  has_many :orders, dependent: :restrict_with_error
  has_many :licenses, dependent: :restrict_with_error
  has_many :refund_requests, dependent: :restrict_with_error
  has_many :processed_refund_requests, class_name: "RefundRequest",
    foreign_key: :processed_by_id, dependent: :restrict_with_error
  has_many :commerce_audit_events, foreign_key: :actor_id, dependent: :restrict_with_error
  has_one :external_account_link, dependent: :restrict_with_error

  enum :role, { user: 0, admin: 1 }

  attr_accessor :terms_accepted

  validates :name, presence: true
  validates :terms_accepted, acceptance: true, on: :create
  validate :password_must_not_be_common, if: -> { password.present? }

  def trial_started_at
    created_at
  end

  def trial_remaining_seconds
    remaining = (trial_started_at + 7.days) - Time.current
    remaining.to_i.positive? ? remaining.to_i : 0
  end

  def trial_days_remaining
    days = (trial_remaining_seconds / 86_400.0).ceil
    days.positive? ? days : 0
  end

  def trial_active?
    trial_remaining_seconds.positive?
  end

  def licensed_for?(product_code, at: Time.current)
    Entitlements::ProductAccess.licensed?(user: self, product_code: product_code, at: at)
  end

  private

  def password_must_not_be_common
    if COMMON_PASSWORDS.include?(password.downcase)
      errors.add(:base, "너무 흔한 비밀번호입니다. 다른 비밀번호를 입력해 주세요.")
    end
  end
end
