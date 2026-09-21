# Handoff 0059 -- price wording for the ProductLine page's price summary.
# Same wording the Season page's purchase box (product_lines/_purchase_box)
# already uses: a 0-won Season reads "무료", a priced one "33,000원".
module ProductSeasonPriceHelper
  def season_price_text(season)
    season.free? ? "무료" : "#{number_with_delimiter(season.price)}원"
  end
end
