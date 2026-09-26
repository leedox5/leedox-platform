module NavigationHelper
  def primary_navigation_items
    return admin_navigation_items if current_user&.admin?
    return signed_in_navigation_items if user_signed_in?

    [ [ "제품", products_path ], [ "가격", pricing_path ] ]
  end

  private

  def admin_navigation_items
    [
      [ "제품", products_path ],
      [ "가격", pricing_path ],
      [ "대시보드", admin_dashboard_path ],
      [ "서비스데스크", service_desk_path ],
      [ "참조", refs_path ],
      [ "사용자관리", admin_users_path ],
      [ "마이페이지", mypage_path ]
    ]
  end

  def signed_in_navigation_items
    [
      [ "제품", products_path ],
      [ "가격", pricing_path ],
      [ "대시보드", dashboard_path ],
      [ "마이페이지", mypage_path ]
    ]
  end
end
