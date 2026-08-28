module CommerceHelper
  # Short, human-writable reference code to ask the customer to leave as the
  # bank transfer memo/depositor name, so an admin can correlate an incoming
  # transfer with the right order without needing the full UUID.
  def manual_transfer_reference(order)
    order.public_id.delete("-").first(8).upcase
  end

  def refund_status_label(status)
    {
      "requested" => "접수",
      "reviewing" => "검토 중",
      "approved" => "승인",
      "rejected" => "거절",
      "processing" => "외부 처리 대기",
      "refunded" => "외부 처리 확인",
      "failed" => "처리 실패"
    }.fetch(status, status)
  end

  def provider_label(provider)
    { "portone" => "카카오페이", "manual" => "무통장입금" }.fetch(provider, provider)
  end
end
