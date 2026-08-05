class Admin::UsersController < Admin::BaseController
  # Antigravity isn't on sale yet -- excluded from the free-grant buttons
  # until there's something to grant access to (handoff 0018 scope).
  FREE_GRANTABLE_PRODUCT_CODES = %w[chatdox claudox].freeze

  def index
    @users = User.order(created_at: :desc)
    # free_access (aistart) is excluded because everyone always has it --
    # per-user status is meaningless. Products with no active offer (e.g.
    # aigravity, pre-sale) are excluded because nobody can hold or lack a
    # subscription to something not yet purchasable -- "미보유" would imply
    # they could buy it, which they can't.
    @products = Product.active.where(free_access: false)
      .joins(:product_offers).merge(ProductOffer.active).distinct.order(:code)
    @grantable_products = @products.select { |product| FREE_GRANTABLE_PRODUCT_CODES.include?(product.code) }
  end

  def update
    @user = User.find(params[:id])
    role = params.dig(:user, :role).to_s

    unless User.roles.key?(role)
      redirect_to admin_users_path, alert: "올바르지 않은 권한입니다."
      return
    end

    if @user == current_user && role != "admin"
      redirect_to admin_users_path, alert: "본인의 관리자 권한은 해제할 수 없습니다."
      return
    end

    @user.role = role
    if @user.save
      redirect_to admin_users_path, notice: "사용자 정보가 수정되었습니다."
    else
      redirect_to admin_users_path, alert: @user.errors.full_messages.to_sentence
    end
  end

  def grant_free_license
    user = User.find(params[:id])
    product = Product.active.find_by(code: params[:product_code])

    unless product && FREE_GRANTABLE_PRODUCT_CODES.include?(product.code)
      redirect_to admin_users_path, alert: "무료 부여할 수 없는 상품입니다."
      return
    end

    Commerce::GrantFreeLicense.call!(user: user, product: product, actor: current_user)
    redirect_to admin_users_path, notice: "#{user.name}님에게 #{product.name} 1년 무료 라이선스를 부여했습니다."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_users_path, alert: e.record.errors.full_messages.to_sentence
  end
end
