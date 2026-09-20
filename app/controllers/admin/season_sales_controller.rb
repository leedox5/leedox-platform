# Handoff 0057 -- price and sale switch for one ProductSeason. All rules live
# in Commerce::SeasonSales (admin-only, audited); this controller only maps
# them to the admin screen. Admin::BaseController restricts the namespace.
class Admin::SeasonSalesController < Admin::BaseController
  before_action :set_season

  def update
    first_time = @season.product.nil?
    was_on = @season.product&.sale_enabled?
    Commerce::SeasonSales.set_price!(season: @season, total_amount: params.dig(:sale, :total_amount), actor: current_user)
    stopped = was_on && !@season.reload.product.sale_enabled?
    notice = if first_time
      "가격을 저장하고 이 Season의 판매 설정을 만들었습니다. 판매는 아직 중지 상태입니다."
    elsif stopped
      "가격을 저장했습니다. 무료(0원)와 유료 사이가 바뀌어 안전을 위해 판매를 중지했습니다. 준비되면 판매(또는 무료 이용 시작)를 다시 열어 주세요."
    else
      "가격을 저장했습니다."
    end
    redirect_back_to_season notice: notice
  rescue Commerce::SeasonSales::Invalid, ActiveRecord::RecordInvalid => e
    redirect_back_to_season alert: e.message
  end

  def start
    Commerce::SeasonSales.start_sale!(season: @season, actor: current_user)
    redirect_back_to_season notice: "판매를 시작했습니다."
  rescue Commerce::SeasonSales::Invalid => e
    redirect_back_to_season alert: e.message
  end

  def stop
    Commerce::SeasonSales.stop_sale!(season: @season, actor: current_user)
    redirect_back_to_season notice: "판매를 중지했습니다. 신규 구매만 막히고 기존 구매자의 이용은 유지됩니다."
  rescue Commerce::SeasonSales::Invalid => e
    redirect_back_to_season alert: e.message
  end

  private

  def set_season
    @season = ProductSeason.find(params[:product_season_id])
  end

  def redirect_back_to_season(**flash)
    redirect_to edit_admin_product_season_path(@season), **flash
  end
end
