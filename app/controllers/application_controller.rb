class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  include Pundit::Authorization

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :store_redirect_location

  helper_method :billing_checkout_path_for, :purchase_checkout_flow?, :purchase_checkout_product, :current_stored_return_to

  private

  def purchase_checkout_flow?
    return_to = current_stored_return_to
    return_to.present? && return_to.start_with?("/billing/checkout")
  end

  def current_stored_return_to
    if params[:redirect_to].present? && valid_local_redirect_path?(params[:redirect_to])
      params[:redirect_to].to_s
    else
      session["user_return_to"]
    end
  end

  def purchase_checkout_product
    return unless purchase_checkout_flow?

    return_to = current_stored_return_to
    if return_to.include?("claudox")
      Product.find_by(code: "claudox")
    else
      Product.find_by(code: "chatdox")
    end
  end

  def store_redirect_location
    if params[:redirect_to].present? && valid_local_redirect_path?(params[:redirect_to])
      store_location_for(:user, params[:redirect_to].to_s)
    end
  end

  def valid_local_redirect_path?(path)
    path_str = path.to_s
    path_str.start_with?("/") && !path_str.start_with?("//")
  end

  # Chatdox omits the :product_code segment (bare /billing/checkout) so every
  # existing link/bookmark/test built before checkout supported other
  # products keeps resolving to the exact same URL.
  def billing_checkout_path_for(product_code)
    product_code.to_s == "chatdox" ? billing_checkout_path : billing_checkout_path(product_code)
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :name ])
    devise_parameter_sanitizer.permit(:account_update, keys: [ :name ])
  end

  def after_sign_in_path_for(resource)
    stored_location_for(resource) || (resource.admin? ? admin_dashboard_path : dashboard_path)
  end

  def after_sign_up_path_for(resource)
    after_sign_in_path_for(resource)
  end

  def user_not_authorized
    flash[:alert] = if current_user.present?
      "이 작업을 할 권한이 없습니다."
    else
      "로그인 후 이용 가능합니다."
    end

    redirect_to(current_user.present? ? root_path : new_user_session_path)
  end
end
