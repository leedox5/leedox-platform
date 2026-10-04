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
  # Handoff 0057/0065 -- a Product may be the commerce side of one ProductLine
  # (price, orders, licenses; before 0065 it hung off a Season). Those Products
  # are not catalog products: they stay out of /pricing, the home page,
  # dashboards and the admin user grants that list the four term-based
  # products (see .standalone).
  has_one :product_line, dependent: :restrict_with_error

  validates :code, presence: true, uniqueness: true,
    format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validates :name, presence: true
  # Handoff 0078 -- the one line under the name on the home and /pricing cards; blank means no line.
  TAGLINE_MAX = 100
  normalizes :tagline, with: ->(tagline) { tagline.to_s.strip.presence }
  validates :tagline, length: { maximum: TAGLINE_MAX, message: "한 줄 설명은 #{TAGLINE_MAX}자까지 쓸 수 있습니다." }

  scope :active, -> { where(active: true) }
  scope :standalone, -> { where.missing(:product_line) }
  # Handoff 0078 -- the standalone products the admin switched onto the home's AI row.
  # /pricing keeps listing every standalone product regardless.
  scope :on_home, -> { standalone.where(show_on_home: true) }

  # A pre-series catalog product (Chatdox, Claudox, ...), as opposed to the commerce side of a
  # ProductLine. Only these have a home switch and a tagline that shows anywhere.
  def standalone?
    product_line.nil?
  end

  def theme
    THEMES.fetch(code) do
      ProductContent.for(code).theme[:accent] rescue "blue"
    end
  end

  def display_order
    DISPLAY_ORDERS.fetch(code, 99)
  end

  # Where a product's own page is (the not-on-sale checkout's "가격 및 이용 기간 보기", the home card, a locked
  # chapter). A series' commerce product follows the series' current address: the stored value is the slug at the
  # time its sale first opened (Commerce::ProductLineSales) and went stale when the slug changed (wsl -> wsl-core).
  # A standalone product (Chatdox, ...) keeps its stored path.
  def landing_page_path
    product_line ? "/products/#{product_line.slug}" : super
  end

  # The commerce side of a ProductLine (one-time price, indefinite license).
  def line_product?
    product_line.present?
  end

  def gateway?
    free_access? || code == "aistart"
  end
end
