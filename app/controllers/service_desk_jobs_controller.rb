class ServiceDeskJobsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_service_desk!

  def create
    service_desk_request = ServiceDeskRequest.find_by(request_number: params[:id].to_i)
    return render(plain: "요청을 찾을 수 없습니다.", status: :not_found) unless service_desk_request

    job = service_desk_request.service_desk_jobs.build(job_params.merge(author: current_user.name))

    if job.save
      redirect_to service_desk_request_path(service_desk_request), notice: "작업 내용이 추가되었습니다."
    else
      redirect_to service_desk_request_path(service_desk_request), alert: job.errors.full_messages.to_sentence
    end
  end

  def edit
    @service_desk_request = ServiceDeskRequest.find_by(request_number: params[:id].to_i)
    return render(plain: "요청을 찾을 수 없습니다.", status: :not_found) unless @service_desk_request

    @job = @service_desk_request.service_desk_jobs.find_by(job_number: params[:job_id].to_i)
    render(plain: "작업을 찾을 수 없습니다.", status: :not_found) unless @job
  end

  def update
    @service_desk_request = ServiceDeskRequest.find_by(request_number: params[:id].to_i)
    return render(plain: "요청을 찾을 수 없습니다.", status: :not_found) unless @service_desk_request

    @job = @service_desk_request.service_desk_jobs.find_by(job_number: params[:job_id].to_i)
    return render(plain: "작업을 찾을 수 없습니다.", status: :not_found) unless @job

    if @job.update(job_params)
      redirect_to service_desk_request_path(@service_desk_request), notice: "작업 내용이 수정되었습니다."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def authorize_service_desk!
    authorize :admin, :access?
  end

  def job_params
    params.require(:service_desk_job).permit(:content)
  end
end
