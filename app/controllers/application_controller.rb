class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  include Pundit::Authorization

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  prepend_before_action :apply_theme_preview
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :store_redirect_location

  helper_method :billing_checkout_path_for, :purchase_checkout_flow?, :purchase_checkout_product, :current_stored_return_to

  private

  # Handoff 0102 (D-014 step 2) -- the light preview: any page opened with ?theme=light (or ?theme=dark to turn it off)
  # remembers the choice in a cookie for a year and sends the visitor on to the same address without the parameter, so
  # the preview address is never what gets bookmarked, shared or indexed. Step 3 (the switch) keeps the same cookie.
  # Any other value of the parameter is left alone. FrameThemeHelper#light_theme? reads the cookie.
  def apply_theme_preview
    mode = params[:theme]
    return unless request.get? && FrameThemeHelper::THEMES.include?(mode)

    cookies[FrameThemeHelper::THEME_COOKIE] = { value: mode, expires: 1.year, path: "/", same_site: :lax,
                                                secure: request.ssl?, httponly: false }
    query = request.query_parameters.except("theme")
    redirect_to(query.empty? ? request.path : "#{request.path}?#{query.to_query}", status: :see_other)
  end

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
  def billing_checkout_path_for(product_code, **options)
    product_code.to_s == "chatdox" ? billing_checkout_path(options) : billing_checkout_path(product_code, options)
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :name, :terms_accepted ])
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
