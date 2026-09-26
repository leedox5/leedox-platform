# Handoff 0068 -- turns a ProductLine's access_state (the same states the detail page's
# purchase box renders, see _purchase_box.html.erb) into the product list's short badge.
# The judgment (which state applies) is shared; only this label text is list-specific.
module ProductLinesHelper
  # (value, label) pairs for the list's filter tabs (0068 R2), in display order. "mine" is
  # appended by the caller only for a signed-in user -- ProductLinesController#FILTERS
  # is the source of truth for which values a request may pass.
  PRODUCT_LIST_FILTERS = [ [ "all", "전체" ], [ "free", "무료" ], [ "paid", "유료" ] ].freeze

  def product_list_filter_options
    user_signed_in? ? PRODUCT_LIST_FILTERS + [ [ "mine", "내 제품" ] ] : PRODUCT_LIST_FILTERS
  end

  def product_list_filter_tab_classes(selected)
    base = "flex-shrink-0 whitespace-nowrap rounded-full px-4 py-1.5 text-sm font-bold transition"
    selected ? "#{base} bg-indigo-600 text-white" : "#{base} bg-white text-slate-600 hover:bg-slate-100"
  end

  def product_list_empty_message(filter)
    case filter
    when "free" then "무료 제품이 아직 없습니다."
    when "paid" then "유료 제품이 아직 없습니다."
    when "mine" then "아직 이용 중인 제품이 없습니다."
    else "곧 새 제품이 공개됩니다."
    end
  end
  def product_list_state_label(state, product_line)
    case state
    when :owned then product_line.free? ? "이용 중" : "보유 중"
    when :free_open then "무료"
    when :for_sale then "#{number_with_delimiter(product_line.price)}원"
    else "준비 중" # :unavailable -- the detail page's longer "현재 시작할/구매할 수 없습니다" doesn't fit a card
    end
  end

  def product_list_state_classes(state)
    base = "flex-shrink-0 whitespace-nowrap rounded-full px-3 py-1 text-xs font-bold"
    case state
    when :owned then "#{base} bg-blue-50 text-blue-700"
    when :free_open then "#{base} bg-emerald-50 text-emerald-700"
    when :for_sale then "#{base} bg-slate-100 text-slate-800"
    else "#{base} bg-amber-50 text-amber-700"
    end
  end
end
