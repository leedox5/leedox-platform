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
  # Handoff 0057 -- a Product may be the commerce side of one ProductSeason
  # (price, orders, licenses). Those Products are not catalog products: they
  # stay out of /pricing, the home page, dashboards and the admin user grants
  # that list the four term-based products (see .standalone).
  has_one :product_season, dependent: :restrict_with_error

  validates :code, presence: true, uniqueness: true,
    format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validates :name, presence: true

  scope :active, -> { where(active: true) }
  # Until the product_seasons.product_id migration has run (a deploy does not
  # run migrations), there can be no Season products yet, so every Product is
  # standalone -- this keeps the home/pricing/dashboard pages working in that
  # window instead of raising on the missing column.
  scope :standalone, -> { ProductSeason.column_names.include?("product_id") ? where.missing(:product_season) : all }

  def theme
    THEMES.fetch(code) do
      ProductContent.for(code).theme[:accent] rescue "blue"
    end
  end

  def display_order
    DISPLAY_ORDERS.fetch(code, 99)
  end

  def season_product?
    ProductSeason.column_names.include?("product_id") && product_season.present?
  end

  def gateway?
    free_access? || code == "aistart"
  end
end
