module Commerce
  class Reconciliation
    DEFAULT_STALE_AFTER = 30.minutes
    Issue = Data.define(:code, :order_public_id, :provider, :status)
    Report = Data.define(:issues, :checked_at, :pending_summary) do
      def ok?
        issues.empty?
      end
    end

    def self.call(stale_after: DEFAULT_STALE_AFTER, at: Time.current, log: true)
      new(stale_after: stale_after, at: at, log: log).call
    end

    def initialize(stale_after:, at:, log:)
      @stale_after = stale_after
      @at = at
      @log = log
      @issues = []
    end

    def call
      orders = Order.includes(:refund_requests, :payment_transaction, order_items: :license).find_each
      orders.each { |order| inspect_order(order) }
      inspect_license_overlaps
      inspect_duplicate_open_refunds
      log_issues if @log
      Report.new(issues: @issues.freeze, checked_at: @at, pending_summary: pending_summary)
    end

    private

    def inspect_order(order)
      transaction = order.payment_transaction
      add_issue(:paid_without_transaction, order) if order.status == "paid" && transaction.blank?
      add_issue(:paid_without_license, order) if order.status == "paid" && order.licenses.empty?
      add_issue(:stale_pending, order) if stale_pending?(order)
      add_issue(:terminal_order_with_license, order) if %w[failed canceled abandoned].include?(order.status) && order.licenses.any?
      add_issue(:payment_amount_mismatch, order) if transaction && transaction.amount != order.total_amount
      add_issue(:order_item_total_mismatch, order) unless order_item_totals_match?(order)
      add_issue(:processed_payment_unfinalized, order) if processed_but_unfinalized?(order, transaction)
      add_issue(:abandoned_provider_success_conflict, order) if abandoned_success_conflict?(order, transaction)
      inspect_refunds(order)
    end

    def stale_pending?(order)
      order.status == "pending" && order.payment_requested_at < (@at - @stale_after)
    end

    def order_item_totals_match?(order)
      items = order.order_items
      items.sum(&:supply_amount) == order.supply_amount &&
        items.sum(&:vat_amount) == order.vat_amount &&
        items.sum(&:total_amount) == order.total_amount
    end

    def processed_but_unfinalized?(order, transaction)
      return false if %w[paid abandoned].include?(order.status) || transaction.blank?

      transaction.status == "active" || successful_provider_status?(transaction.provider_payload)
    end

    def successful_provider_status?(payload)
      %w[DONE PAID].include?(payload.to_h["status"])
    end

    def abandoned_success_conflict?(order, transaction)
      order.status == "abandoned" && transaction.present? && (
        %w[DONE PAID].include?(transaction.provider_status) ||
        successful_provider_status?(transaction.provider_payload) ||
        transaction.status == "active"
      )
    end

    def inspect_refunds(order)
      requests = order.refund_requests.to_a
      add_issue(:paid_order_open_refund, order) if order.status == "paid" && requests.any?(&:open?)
      requests.select { |request| request.status == "refunded" }.each do |request|
        add_issue(:refund_without_provider_confirmation, order) unless request.external_refund_confirmed?
        add_issue(:refunded_license_policy_unresolved, order) if request.external_refund_confirmed? && order.licenses.not_canceled.any?
      end
    end

    def inspect_duplicate_open_refunds
      RefundRequest.open.group(:order_id).having("COUNT(*) > 1").count.each_key do |order_id|
        add_issue(:duplicate_open_refund_requests, Order.find_by(id: order_id))
      end
    end

    def pending_summary
      pending = Order.where(status: "pending")
      stale = pending.where("payment_requested_at < ?", @at - @stale_after).count
      { fresh: pending.count - stale, stale: stale }.freeze
    end

    def inspect_license_overlaps
      License.not_canceled.includes(order_item: :order).order(:user_id, :product_id, :starts_on)
        .group_by { |license| [ license.user_id, license.product_id ] }
        .each_value do |licenses|
          licenses.each_cons(2) do |previous, current|
            next if current.starts_on > previous.last_usable_on

            order = current.order_item&.order || previous.order_item&.order
            add_issue(:overlapping_license, order, provider: order&.provider, status: current.effective_status(at: @at))
          end
        end
    end

    def add_issue(code, order = nil, provider: order&.provider, status: order&.status || "unknown")
      @issues << Issue.new(
        code: code.to_s,
        order_public_id: order&.public_id || "-",
        provider: provider.presence || "unknown",
        status: status
      )
    end

    def log_issues
      @issues.each do |issue|
        Commerce::EventLogger.log(
          event: "commerce.reconciliation_anomaly.#{issue.code}",
          provider: issue.provider,
          order: Order.find_by(public_id: issue.order_public_id),
          status: issue.status,
          at: @at
        )
      end
    end
  end
end
