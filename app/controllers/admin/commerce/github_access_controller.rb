class Admin::Commerce::GithubAccessController < Admin::BaseController
  before_action :ensure_v1_boundary!

  def index
    links = ExternalAccountLink.includes(:user).order(created_at: :asc).to_a
    active_user_ids = active_chatdox_license_user_ids

    @needs_invite = links.select { |link| link.needs_invite? && active_user_ids.include?(link.user_id) }
    @needs_revoke = links.select { |link| link.needs_revoke? && !active_user_ids.include?(link.user_id) }
  end

  def invite
    link = ExternalAccountLink.find_by!(public_id: params[:id])
    link.update!(invited_at: Time.current)
    redirect_to admin_commerce_github_access_path, notice: "초대 완료로 기록했습니다."
  end

  def revoke
    link = ExternalAccountLink.find_by!(public_id: params[:id])
    link.update!(revoked_at: Time.current)
    redirect_to admin_commerce_github_access_path, notice: "회수 완료로 기록했습니다."
  end

  private

  def ensure_v1_boundary!
    redirect_to admin_dashboard_path, alert: "GitHub Lab 운영 기능은 현재 V1 제공 범위에 포함되지 않습니다."
  end

  def active_chatdox_license_user_ids
    License.for_product("chatdox").not_canceled.select { |license| license.active_at? }.map(&:user_id).to_set
  end
end
