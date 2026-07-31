class ServiceDeskController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_service_desk!

  def index
    @requests = ServiceDeskRequest.visible.includes(:service_desk_jobs).order(request_number: :desc)
    @my_related_requests = @requests.select { |request| my_related?(request) }
    @new_requests = @requests.select(&:pending?)
  end

  def show
    @requests = ServiceDeskRequest.visible.order(:request_number)
    @current_request = ServiceDeskRequest.visible.find_by(request_number: params[:id].to_i)

    unless @current_request
      render plain: "요청을 찾을 수 없거나 공개되지 않았습니다.", status: :not_found
      return
    end

    current_index = @requests.to_a.index(@current_request)
    @prev_request = current_index&.positive? ? @requests[current_index - 1] : nil
    @next_request = current_index && @requests[current_index + 1]

    # Plain ServiceDeskJob.new with no association assigned — building it off
    # @current_request.service_desk_jobs (or even just assigning
    # service_desk_request: @current_request, since the model declares
    # inverse_of) pushes this blank record into the association's in-memory
    # target, so the view's `service_desk_jobs.each` below renders it too
    # (with a nil performed_at, since that's only assigned on validation/save).
    # The form only needs this for field/error rendering — actual creation
    # happens in ServiceDeskJobsController#create against a separate object.
    @new_job = ServiceDeskJob.new
  end

  def new
    @service_desk_request = ServiceDeskRequest.new
  end

  def create
    @service_desk_request = ServiceDeskRequest.new(service_desk_request_params.merge(requester: current_user.name))

    if @service_desk_request.save
      redirect_to service_desk_request_path(@service_desk_request), notice: "티켓이 발행되었습니다."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @service_desk_request = ServiceDeskRequest.find_by(request_number: params[:id].to_i)
    render(plain: "요청을 찾을 수 없습니다.", status: :not_found) unless @service_desk_request
  end

  def update
    @service_desk_request = ServiceDeskRequest.find_by(request_number: params[:id].to_i)
    return render(plain: "요청을 찾을 수 없습니다.", status: :not_found) unless @service_desk_request

    if @service_desk_request.update(service_desk_request_update_params)
      redirect_to service_desk_request_path(@service_desk_request), notice: "티켓이 수정되었습니다."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def export
    send_data ServiceDeskExport.new.to_zip, filename: "service-desk-export-#{Time.current.strftime('%Y%m%d-%H%M%S')}.zip",
                                             type: "application/zip"
  end

  private

  def authorize_service_desk!
    authorize :admin, :access?
  end

  def my_related?(request)
    request.requester == current_user.name || request.service_desk_jobs.any? { |job| job.author == current_user.name }
  end

  def service_desk_request_params
    params.require(:service_desk_request).permit(:subject, :visibility, :description)
  end

  def service_desk_request_update_params
    params.require(:service_desk_request).permit(:subject, :description, :status, :visibility)
  end
end
