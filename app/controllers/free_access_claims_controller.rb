# Handoff 0057 (Season) / 0065 (ProductLine) -- the explicit "무료 이용 시작" action
# for a 0-won product. POST-only, signed-in users only; all rules live in
# Commerce::ClaimFreeAccess.
class FreeAccessClaimsController < ApplicationController
  before_action :authenticate_user!

  def create
    product = Product.find_by!(code: params[:product_code])
    line = product&.product_line
    return redirect_to(root_path, alert: "무료로 시작할 수 없는 상품입니다.") unless line

    result = Commerce::ClaimFreeAccess.call!(user: current_user, product_line: line)
    notice = result.created ? "무료 이용을 시작했습니다. 이 제품을 계속 이용하실 수 있습니다." : "이미 이용 중인 제품입니다."
    redirect_to product_line_path(line.slug), notice: notice
  rescue Commerce::ClaimFreeAccess::Unavailable
    redirect_to(product_line_path(line.slug), alert: "지금은 무료로 시작할 수 없습니다.")
  end
end
