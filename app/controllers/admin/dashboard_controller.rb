class Admin::DashboardController < Admin::BaseController
  def show
    @total_users = User.count
    @admin_users = User.admin.count
    @active_licenses = License.not_canceled.where("access_ends_at > ?", Time.current).count
    @trial_users = User.where(created_at: 7.days.ago..).count
    @recent_users = User.order(created_at: :desc).limit(5)
    @recent_transactions = PaymentTransaction.order(created_at: :desc).limit(5)
    @open_refund_requests_count = RefundRequest.open.count
  end
end
