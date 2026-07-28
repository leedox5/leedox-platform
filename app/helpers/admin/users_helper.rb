module Admin::UsersHelper
  # Admin-only period display -- deliberately separate from
  # DashboardHelper#product_period_text (customer-facing, long-form Korean
  # date), so changing this format never touches what customers see.
  def license_period_text(user, product)
    return "-" if product.free_access?

    license = user.licenses.for_product(product.code).not_canceled.find { |item| item.active_at? }
    return "없음" unless license

    "#{license.starts_on.strftime('%Y.%m.%d')} ~ #{license.last_usable_on.strftime('%Y.%m.%d')}"
  end
end
