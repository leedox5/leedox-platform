# Handoff 0057 -- the explicit "무료 이용 시작" action for a 0-won Season.
# POST-only, signed-in users only; all rules live in Commerce::ClaimFreeSeason.
class FreeSeasonClaimsController < ApplicationController
  before_action :authenticate_user!

  def create
    product = Product.find_by!(code: params[:product_code])
    season = product.product_season
    return redirect_to(root_path, alert: "무료로 시작할 수 없는 상품입니다.") unless season

    result = Commerce::ClaimFreeSeason.call!(user: current_user, season: season)
    notice = result.created ? "무료 이용을 시작했습니다. 이 Season을 계속 이용하실 수 있습니다." : "이미 이용 중인 Season입니다."
    redirect_to product_season_path(season.product_line.slug, season.slug), notice: notice
  rescue Commerce::ClaimFreeSeason::Unavailable
    redirect_to(product_season_path(season.product_line.slug, season.slug), alert: "지금은 무료로 시작할 수 없습니다.")
  end
end
