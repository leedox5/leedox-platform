class PremiumWaitlist < ApplicationRecord
  before_validation :normalize_email

  validates :email,
    presence: true,
    format: { with: URI::MailTo::EMAIL_REGEXP },
    uniqueness: { case_sensitive: false }
  validates :source, presence: true

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
