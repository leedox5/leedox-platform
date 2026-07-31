class PremiumWaitlistsController < ApplicationController
  def create
    waitlist = PremiumWaitlist.find_or_initialize_by(email: waitlist_params[:email].to_s.strip.downcase)
    waitlist.source = waitlist_params[:source].presence || "landing_pricing"

    if waitlist.persisted?
      redirect_back fallback_location: root_path(anchor: "pricing"), notice: "이미 오픈 알림이 등록된 이메일입니다."
      return
    end

    if waitlist.save
      redirect_back fallback_location: root_path(anchor: "pricing"), notice: "프리미엄 오픈 알림 신청이 완료되었습니다."
    else
      redirect_back fallback_location: root_path(anchor: "pricing"), alert: "이메일 주소를 다시 확인해 주세요."
    end
  end

  private

  def waitlist_params
    params.require(:premium_waitlist).permit(:email, :source)
  end
end
