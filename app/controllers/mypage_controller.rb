class MypageController < ApplicationController
  before_action :authenticate_user!

  ORDERS_PER_PAGE = 10

  # Handoff 0081 -- one card per product (a series' commerce product = that series).
  # Handoff 0082 -- split in two: series (all of them, as in 0081) and earlier products (standalone,
  # paid, and only while in use or scheduled -- no expired, no free, no past records).
  LicenseCard = Struct.new(:product, :title, :status, :license, :past, :link, :sort_key, keyword_init: true)
  STATUS_ORDER = { "active" => 0, "scheduled" => 1, "expired" => 2 }.freeze

  def show
    @licenses = current_user.licenses.includes(product: :product_line).order(starts_on: :asc)
    @orders_page = [ params[:orders_page].to_i, 1 ].max
    orders_scope = current_user.orders
      .includes(:order_items, :refund_requests, order_items: :license)
      .order(created_at: :desc)
    @orders = orders_scope.offset((@orders_page - 1) * ORDERS_PER_PAGE).limit(ORDERS_PER_PAGE)
    @has_more_orders = orders_scope.offset(@orders_page * ORDERS_PER_PAGE).limit(1).exists?
    @series_cards, @legacy_cards = license_cards
  end

  private

  # Every judgment is an existing one: License#effective_status (the badge this page always showed),
  # License.longest_running / .latest_expired (the dashboard's period line, 0080), ProductLine.
  # customer_reachable (the episode gate's scope) for whether a series link is shown, and
  # Product#free_access? (what made a 무료 이용 card in 0081) for "paid".
  def license_cards
    reachable_line_ids = ProductLine.customer_reachable
      .where(product_id: @licenses.map(&:product_id).uniq).pluck(:id).to_set
    cards = @licenses.group_by(&:product).filter_map { |product, licenses| license_card(product, licenses, reachable_line_ids) }
    series, standalone = cards.partition { |card| card.product.product_line }

    legacy = standalone
      .select { |card| !card.product.free_access? && %w[active scheduled].include?(card.status) }
      .each { |card| card.past = [] } # past records stay in the order history (Tommy, 0082)
    [ series.sort_by(&:sort_key), legacy.sort_by(&:sort_key) ]
  end

  # A product with only canceled licenses gets no card (the order history keeps them).
  def license_card(product, licenses, reachable_line_ids)
    by_status = licenses.group_by(&:effective_status)
    status = %w[active scheduled expired].find { |s| by_status[s].present? }
    return nil unless status

    representative = case status
    when "active" then License.longest_running(by_status["active"])
    when "scheduled" then by_status["scheduled"].min_by(&:starts_on)
    else License.latest_expired(licenses)
    end
    line = product.product_line
    sort_key = case status
    when "active" then [ STATUS_ORDER["active"], -by_status["active"].map(&:starts_on).max.jd, product.id ]
    when "scheduled" then [ STATUS_ORDER["scheduled"], representative.starts_on.jd, product.id ]
    else [ STATUS_ORDER["expired"], -representative.last_usable_on.jd, product.id ]
    end

    LicenseCard.new(
      product: product,
      # A series' current customer-facing name (as on the dashboard); the commerce product's own name
      # (copied when the sale opened) only when the series link is gone.
      title: line&.customer_name.presence || product.name,
      status: status,
      license: representative,
      past: (licenses - [ representative ]).sort_by { |license| [ -license.starts_on.jd, -license.id ] },
      link: status == "active" ? card_link(product, line, reachable_line_ids) : nil,
      sort_key: sort_key
    )
  end

  # 콘텐츠 보기: a series' page if a customer can open it; a standalone product's own page.
  def card_link(product, line, reachable_line_ids)
    return (reachable_line_ids.include?(line.id) ? product_line_path(line.slug) : nil) if line

    product.landing_page_path.presence
  end
end
