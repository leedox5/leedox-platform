# Handoff 0053 R3 -- minimal admin authoring for DB-backed content bundles.
# Admin::BaseController already restricts this whole namespace to
# authenticated admins (see its authenticate_user!/authorize_admin!), which
# is all R3 asks for here -- no author/reviewer/publisher role split.
class Admin::ContentBundlesController < Admin::BaseController
  def index
    @bundles = ContentBundle.order(:position, :id)
  end

  def new
    @bundle = ContentBundle.new
  end

  def create
    @bundle = ContentBundle.new(bundle_params)
    if @bundle.save
      redirect_to edit_admin_content_bundle_path(@bundle), notice: "콘텐츠 묶음을 만들었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @bundle = ContentBundle.find(params[:id])
    @episodes = @bundle.content_episodes.ordered
  end

  def update
    @bundle = ContentBundle.find(params[:id])
    if @bundle.update(bundle_params)
      redirect_to edit_admin_content_bundle_path(@bundle), notice: "저장했습니다."
    else
      @episodes = @bundle.content_episodes.ordered
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def bundle_params
    params.require(:content_bundle).permit(:internal_name, :customer_title, :status, :position, :product_id)
  end
end
