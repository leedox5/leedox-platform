class PagesController < ApplicationController
  def home
    # Static landing page: no database query required.
  end

  def chatdox
    # Pricing is rendered by shared/_product_pricing, which looks up the
    # product/offers/sales-enabled state itself from product_code alone.
  end

  def aigravity; end

  def getting_started; end

  def pricing
    @products = Product.order(:code).sort_by { |product| [ pricing_rank(product), product.code ] }
  end

  def community; end

  def login; end

  def terms; end

  def privacy; end

  private

  # /pricing's card order (handoff 0019): on sale first, then free, then
  # everything still prepping -- ahead of the plain code-alphabetical order,
  # so a not-yet-purchasable product (e.g. Antigravity) never happens to
  # sort ahead of what's actually buyable right now.
  def pricing_rank(product)
    return 0 if Commerce::Sales.enabled_for?(product)
    return 1 if product.free_access?

    2
  end
end
