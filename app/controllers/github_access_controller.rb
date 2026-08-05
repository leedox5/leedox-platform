class GithubAccessController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_v1_boundary!

  def show
    @link = current_user.external_account_link
  end

  def create
    if current_user.external_account_link.present?
      redirect_to github_access_path, alert: "이미 연결된 GitHub 계정이 있습니다."
      return
    end

    link = ExternalAccountLink.new(user: current_user, username: link_params.fetch(:username))
    if link.save
      redirect_to github_access_path, notice: "GitHub 계정을 연결했습니다."
    else
      redirect_to github_access_path, alert: "GitHub 사용자명을 확인해 주세요."
    end
  end

  private

  def ensure_v1_boundary!
    redirect_to dashboard_path, alert: "GitHub Lab 연결 기능은 현재 V1 제공 범위에 포함되지 않습니다."
  end

  def link_params
    params.require(:external_account_link).permit(:username)
  end
end
