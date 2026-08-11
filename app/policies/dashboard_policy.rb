class DashboardPolicy < ApplicationPolicy
  def access?
    user.present?
  end

  def admin_access?
    user&.admin?
  end
end
