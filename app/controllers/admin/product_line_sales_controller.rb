# Handoff 0057 (Season) / 0065 (ProductLine) -- price and sale switch for one
# product line. All rules live in Commerce::ProductLineSales (admin-only,
# audited); this controller only maps them to the admin screen.
# Admin::BaseController restricts the namespace.
class Admin::ProductLineSalesController < Admin::BaseController
  before_action :set_product_line

  def update
    first_time = @product_line.product.nil?
    was_on = @product_line.product&.sale_enabled?
    Commerce::ProductLineSales.set_price!(product_line: @product_line, total_amount: params.dig(:sale, :total_amount), actor: current_user)
    stopped = was_on && !@product_line.reload.product.sale_enabled?
    notice = if first_time
      "가격을 저장하고 이 제품의 판매 설정을 만들었습니다. 판매는 아직 중지 상태입니다."
    elsif stopped
      "가격을 저장했습니다. 무료(0원)와 유료 사이가 바뀌어 안전을 위해 판매를 중지했습니다. 준비되면 판매(또는 무료 이용 시작)를 다시 열어 주세요."
    else
      "가격을 저장했습니다."
    end
    redirect_back_to_product_line notice: notice
  rescue Commerce::ProductLineSales::Invalid, ActiveRecord::RecordInvalid => e
    redirect_back_to_product_line alert: e.message
  end

  def start
    Commerce::ProductLineSales.start_sale!(product_line: @product_line, actor: current_user)
    redirect_back_to_product_line notice: "판매를 시작했습니다."
  rescue Commerce::ProductLineSales::Invalid => e
    redirect_back_to_product_line alert: e.message
  end

  def stop
    Commerce::ProductLineSales.stop_sale!(product_line: @product_line, actor: current_user)
    redirect_back_to_product_line notice: "판매를 중지했습니다. 신규 구매만 막히고 기존 구매자의 이용은 유지됩니다."
  rescue Commerce::ProductLineSales::Invalid => e
    redirect_back_to_product_line alert: e.message
  end

  private

  def set_product_line
    @product_line = ProductLine.find(params[:product_line_id])
  end

  def redirect_back_to_product_line(**flash)
    redirect_to edit_admin_product_line_path(@product_line, anchor: "sale-settings"), **flash
  end
end
