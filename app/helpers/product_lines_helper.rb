# Handoff 0068 -- turns a ProductLine's access_state (the same states the detail page's
# purchase box renders, see _purchase_box.html.erb) into the product list's short badge.
# The judgment (which state applies) is shared; only this label text is list-specific.
module ProductLinesHelper
  # (value, label) pairs for the list's filter tabs (0068 R2), in display order. "mine" is
  # appended by the caller only for a signed-in user -- ProductLinesController#FILTERS
  # is the source of truth for which values a request may pass.
  PRODUCT_LIST_FILTERS = [ [ "all", "전체" ], [ "free", "무료" ], [ "paid", "유료" ] ].freeze

  def product_list_filter_options
    user_signed_in? ? PRODUCT_LIST_FILTERS + [ [ "mine", "내 시리즈" ] ] : PRODUCT_LIST_FILTERS
  end

  # Handoff 0083 -- the series list is dark (the home's palette); these two helpers are used only there.
  def product_list_filter_tab_classes(selected)
    base = "flex-shrink-0 whitespace-nowrap rounded-full px-4 py-1.5 text-sm font-bold transition"
    selected ? "#{base} bg-[#f0a53c] text-[#0e1014]" : "#{base} border border-white/15 bg-[#15181e] text-[#c9c4ba] hover:border-white/30 hover:text-[#f2efe8]"
  end

  def product_list_empty_message(filter)
    case filter
    when "free" then "무료 시리즈가 아직 없습니다."
    when "paid" then "유료 시리즈가 아직 없습니다."
    when "mine" then "아직 이용 중인 시리즈가 없습니다."
    else "곧 새 시리즈가 공개됩니다."
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

  # Handoff 0071 -- the label of the button that opens a series at its first published episode (the
  # home hero's main button; the member dashboard's series card shares it since 0080).
  SERIES_START_LABEL = "첫 편부터 보기".freeze

  def series_start_label = SERIES_START_LABEL

  # Handoff 0071 -- the hero's release line: "공개 2편 · 공개 예정 3편", or just "공개 N편" when nothing
  # is coming up. Counts, not episode numbers -- visitors never see a number (position is only an
  # ordering key and can be 0). Published = what the product page lists; 공개 예정 =
  # ProductLine#upcoming_episodes.
  def series_release_label(published, upcoming)
    return "공개 #{published.size}편" if upcoming.empty?

    parts = []
    parts << "공개 #{published.size}편" if published.any?
    parts << "공개 예정 #{upcoming.size}편"
    parts.join(" · ")
  end

  def product_list_state_classes(state)
    base = "flex-shrink-0 whitespace-nowrap rounded-full border px-3 py-1 text-xs font-bold"
    case state
    when :owned then "#{base} border-[#f0a53c]/40 bg-[#f0a53c]/10 text-[#f0a53c]"
    when :free_open then "#{base} border-[#7dd3a8]/40 bg-[#7dd3a8]/10 text-[#7dd3a8]"
    when :for_sale then "#{base} border-white/20 bg-white/5 text-[#f2efe8]"
    else "#{base} border-white/10 bg-transparent text-[#a8a39a]"
    end
  end
end
