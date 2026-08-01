class Admin::ChatdoxReadinessController < Admin::BaseController
  def show
    @readiness = ChatdoxRelease::Readiness.call
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
  end
end
