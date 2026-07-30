class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  include Pundit::Authorization

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :configure_permitted_parameters, if: :devise_controller?

  helper_method :billing_checkout_path_for

  private

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

  def user_not_authorized
    flash[:alert] = if current_user.present?
      "이 작업을 할 권한이 없습니다."
    else
      "로그인 후 이용 가능합니다."
    end

    redirect_to(current_user.present? ? root_path : new_user_session_path)
  end
end
