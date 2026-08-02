class PagesController < ApplicationController
  def home
    # Static landing page: no database query required.
  end

  def chatdox
    # Pricing is rendered by shared/_product_pricing, which looks up the
    # product/offers/sales-enabled state itself from product_code alone.
  end

  def getting_started; end

  def pricing
    @products = Product.order(:code)
  end

  def community; end

  def login; end

  def terms; end

  def privacy; end
end
