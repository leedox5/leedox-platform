class Admin::Commerce::ProductsController < Admin::BaseController
  def index
    @products = Product.includes(:product_offers).order(:code)
  end

  def edit
    @product = Product.find(params[:id])
    ensure_offers_exist_for(@product)
  end

  def update
    @product = Product.find(params[:id])

    if params[:product].present?
      ActiveRecord::Base.transaction do
        @product.update!(product_params)
        update_offers_for(@product)
      end
      from_state = "configured"
      to_state = "updated"
      action_name = "product_pricing_updated"
      notice_msg = "#{@product.name}의 요금 및 설정이 성공적으로 저장되었습니다."
    else
      from_state = @product.sale_enabled? ? "enabled" : "disabled"
      @product.update!(sale_enabled: !@product.sale_enabled?)
      to_state = @product.sale_enabled? ? "enabled" : "disabled"
      action_name = "product_sale_toggled"
      notice_msg = "#{@product.name}의 판매 상태를 변경했습니다."
    end

    Commerce::AuditRecorder.record!(
      actor: current_user,
      action: action_name,
      auditable: @product,
      from_state: from_state,
      to_state: to_state
    )

    redirect_to admin_commerce_products_path, notice: notice_msg
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = "저장 중 오류가 발생했습니다: #{e.message}"
    ensure_offers_exist_for(@product)
    render :edit, status: :unprocessable_entity
  end

  private

  def product_params
    params.require(:product).permit(:name, :sale_enabled, :free_access, :guest_chapter_limit, :trial_chapter_limit, :active)
  end

  def ensure_offers_exist_for(product)
    [ 1, 3, 6, 12 ].each do |months|
      product.product_offers.find_or_create_by!(duration_months: months, version: 1) do |offer|
        offer.code = "#{product.code}-#{months}m-v1"
        offer.total_amount = 0
        offer.supply_amount = 0
        offer.vat_amount = 0
        offer.discount_bps = 0
        offer.currency = "KRW"
        offer.active = true
      end
    end
  end

  def update_offers_for(product)
    offers_param = params.dig(:product, :offers_attributes) || {}
    offers_param.each do |_idx, offer_attrs|
      duration = offer_attrs[:duration_months].to_i
      next unless [ 1, 3, 6, 12 ].include?(duration)

      total = offer_attrs[:total_amount].to_i
      discount_pct = offer_attrs[:discount_pct].to_f
      is_active = offer_attrs[:active] == "1" || offer_attrs[:active] == true

      supply = (total / 1.1).round
      vat = total - supply
      discount_bps = (discount_pct * 100).round.clamp(0, 10000)

      offer = product.product_offers.find_or_initialize_by(duration_months: duration, version: 1)
      offer.code = "#{product.code}-#{duration}m-v1" if offer.code.blank?
      offer.currency = "KRW" if offer.currency.blank?
      offer.total_amount = total
      offer.supply_amount = supply
      offer.vat_amount = vat
      offer.discount_bps = discount_bps
      offer.active = is_active
      offer.save!
    end
  end
end
