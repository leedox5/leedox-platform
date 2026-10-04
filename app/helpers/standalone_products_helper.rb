# The sale state of a standalone (non-ProductLine) product -- Chatdox, Claudox, aistart,
# Antigravity -- as /pricing has always shown it (handoff 0019). Pulled out of the pricing view in
# handoff 0071 so the home's "AI와 함께 만들기" row shows these products with exactly the same
# badge and price line, never a second copy of the rule.
module StandaloneProductsHelper
  # state: :free (무료 이용 가능), :on_sale (판매 중) or :preparing (준비 중).
  def standalone_product_state(product)
    return :free if product.free_access?
    return :on_sale if Commerce::Sales.enabled_for?(product)

    :preparing
  end

  def standalone_product_badge(product)
    { free: "무료 이용 가능", on_sale: "판매 중", preparing: "준비 중" }.fetch(standalone_product_state(product))
  end

  # The main button on a standalone product card (it goes to the product's own page): a free product
  # invites a start, anything else asks for a closer look. /pricing and the member dashboard (0079)
  # share this.
  def standalone_product_cta_label(product)
    product.free_access? ? "무료로 시작하기" : "자세히 보기"
  end

  def standalone_product_price(product)
    return "무료" if product.free_access?

    cheapest_offer = product.product_offers.active.ordered.first
    cheapest_offer ? "최저 #{number_with_delimiter(cheapest_offer.total_amount)}원부터" : "가격 준비 중"
  end
end
