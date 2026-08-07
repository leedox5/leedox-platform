class Product < ApplicationRecord
  THEMES = {
    "chatdox" => "blue",
    "claudox" => "violet",
    "aigravity" => "emerald",
    "aistart" => "teal"
  }.freeze

  DISPLAY_ORDERS = {
    "aistart" => 1,
    "chatdox" => 2,
    "claudox" => 3,
    "aigravity" => 4
  }.freeze

  has_many :product_offers, dependent: :restrict_with_error
  has_many :order_items, dependent: :restrict_with_error
  has_many :licenses, dependent: :restrict_with_error

  validates :code, presence: true, uniqueness: true,
    format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validates :name, presence: true

  scope :active, -> { where(active: true) }

  def theme
    THEMES.fetch(code) do
      ProductContent.for(code).theme[:accent] rescue "blue"
    end
  end

  def display_order
    DISPLAY_ORDERS.fetch(code, 99)
  end

  def gateway?
    free_access? || code == "aistart"
  end
end
