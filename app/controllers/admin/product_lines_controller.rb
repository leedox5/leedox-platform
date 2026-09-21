# Handoff 0056 R3 -- admin CRUD for ProductLine, the single entry point of
# the new-product flow (ProductLine -> ProductSeason -> Episode).
# Admin::BaseController already restricts this whole namespace to
# authenticated admins.
class Admin::ProductLinesController < Admin::BaseController
  include StorageUploadFailure

  def index
    @product_lines = ProductLine.order(:id).with_attached_cover_image
  end

  # Admin-only preview: shows the customer-facing product info and every
  # Season regardless of lifecycle state (the customer route only shows
  # published ones -- see ProductLinesController).
  def show
    @product_line = ProductLine.find(params[:id])
    @seasons = @product_line.product_seasons.ordered
  end

  def new
    @product_line = ProductLine.new
  end

  def create
    @product_line = ProductLine.new(product_line_params)
    if @product_line.save
      redirect_to edit_admin_product_line_path(@product_line), notice: "제품을 만들었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  rescue StandardError => e
    raise unless storage_upload_failed?(e)

    render_storage_upload_failure(e, record: @product_line, attribute: :cover_image, view: :new)
  end

  def edit
    @product_line = ProductLine.find(params[:id])
    @seasons = @product_line.product_seasons.ordered
  end

  def update
    @product_line = ProductLine.find(params[:id])
    if @product_line.update(product_line_params)
      redirect_to edit_admin_product_line_path(@product_line), notice: "저장했습니다."
    else
      @seasons = @product_line.product_seasons.ordered
      render :edit, status: :unprocessable_entity
    end
  rescue StandardError => e
    raise unless storage_upload_failed?(e)

    @seasons = @product_line.product_seasons.ordered
    render_storage_upload_failure(e, record: @product_line, attribute: :cover_image, view: :edit)
  end

  private

  def product_line_params
    params.require(:product_line).permit(:internal_name, :customer_name, :slug, :introduction, :ai_supporter, :status, :cover_image, :cover_image_alt)
  end
end
