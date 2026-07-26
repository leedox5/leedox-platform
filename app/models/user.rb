class User < ApplicationRecord
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

  validates :name, presence: true

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
end
