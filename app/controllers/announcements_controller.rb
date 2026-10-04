# Handoff 0077 -- the public notice list and pages (/notices). No sign-in, no license, no role
# branch: everyone sees the same published notices. An unpublished one is a 404 here for
# everybody, admins included -- admins preview from Admin::AnnouncementsController#preview.
class AnnouncementsController < ApplicationController
  def index
    @announcements = Announcement.listed.to_a
  end

  def show
    @announcement = Announcement.find_by(id: params[:id], published: true)
    render plain: "공지를 찾을 수 없습니다.", status: :not_found unless @announcement
  end
end
