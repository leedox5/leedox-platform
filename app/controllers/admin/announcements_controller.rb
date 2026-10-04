# Handoff 0077 -- writing notices. Admin::BaseController restricts this to admins. Unpublishing is
# the 게시 checkbox; delete is for mistakes.
class Admin::AnnouncementsController < Admin::BaseController
  before_action :set_announcement, only: %i[edit update destroy preview]

  def index
    @announcements = Announcement.order(pinned: :desc, created_at: :desc, id: :desc).to_a
  end

  def new
    @announcement = Announcement.new
  end

  def create
    @announcement = Announcement.new(announcement_params)
    if @announcement.save
      redirect_to edit_admin_announcement_path(@announcement), notice: "공지를 만들었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @announcement.update(announcement_params)
      redirect_to edit_admin_announcement_path(@announcement), notice: "저장했습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @announcement.destroy!
    redirect_to admin_announcements_path, notice: "공지를 삭제했습니다."
  end

  # The customer page's look, for any notice (unpublished included), inside the admin area.
  def preview
    render "announcements/show", locals: { preview: true }
  end

  private

  def set_announcement
    @announcement = Announcement.find(params[:id])
  end

  def announcement_params
    params.require(:announcement).permit(:title, :body, :published, :pinned)
  end
end
