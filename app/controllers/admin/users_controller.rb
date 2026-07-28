class Admin::UsersController < Admin::BaseController
  def index
    @users = User.order(created_at: :desc)
    @products = Product.active.order(:code)
  end

  def update
    @user = User.find(params[:id])

    unless User.roles.key?(user_params[:role])
      redirect_to admin_users_path, alert: "올바르지 않은 권한입니다."
      return
    end

    if @user == current_user && user_params[:role] != "admin"
      redirect_to admin_users_path, alert: "본인의 관리자 권한은 해제할 수 없습니다."
      return
    end

    if @user.update(user_params)
      redirect_to admin_users_path, notice: "사용자 정보가 수정되었습니다."
    else
      redirect_to admin_users_path, alert: @user.errors.full_messages.to_sentence
    end
  end

  private

  def user_params
    params.require(:user).permit(:role)
  end
end
