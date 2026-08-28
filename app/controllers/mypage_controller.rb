class MypageController < ApplicationController
  before_action :authenticate_user!

  ORDERS_PER_PAGE = 10

  def show
    @licenses = current_user.licenses.includes(:product).order(starts_on: :asc)
    @orders_page = [ params[:orders_page].to_i, 1 ].max
    orders_scope = current_user.orders
      .includes(:order_items, :refund_requests, order_items: :license)
      .order(created_at: :desc)
    @orders = orders_scope.offset((@orders_page - 1) * ORDERS_PER_PAGE).limit(ORDERS_PER_PAGE)
    @has_more_orders = orders_scope.offset(@orders_page * ORDERS_PER_PAGE).limit(1).exists?
    @free_products = Product.active.where(free_access: true).order(:code)
  end
end
