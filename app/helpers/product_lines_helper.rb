# Handoff 0068 -- turns a ProductLine's access_state (the same states the detail page's
# purchase box renders, see _purchase_box.html.erb) into the product list's short badge.
# The judgment (which state applies) is shared; only this label text is list-specific.
module ProductLinesHelper
  # (value, label) pairs for the list's filter tabs (0068 R2), in display order. "mine" is
  # appended by the caller only for a signed-in user -- ProductLinesController#FILTERS
  # is the source of truth for which values a request may pass.
  PRODUCT_LIST_FILTERS = [ [ "all", "전체" ], [ "free", "무료" ], [ "paid", "유료" ] ].freeze

  def product_list_filter_options
    user_signed_in? ? PRODUCT_LIST_FILTERS + [ [ "mine", "내 가이드" ] ] : PRODUCT_LIST_FILTERS
  end

  # Handoff 0083 -- the series list is dark (the home's palette); these two helpers are used only there.
  def product_list_filter_tab_classes(selected)
    base = "flex-shrink-0 whitespace-nowrap rounded-full px-4 py-1.5 text-sm font-bold transition"
    selected ? "#{base} bg-accent text-on-accent" : "#{base} border border-line/15 bg-card text-ink-2 hover:border-line/30 hover:text-ink"
  end

  def product_list_empty_message(filter)
    case filter
    when "free" then "무료 가이드가 아직 없습니다."
    when "paid" then "유료 가이드가 아직 없습니다."
    when "mine" then "아직 이용 중인 가이드가 없습니다."
    else "곧 새 가이드가 공개됩니다."
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

  # Handoff 0090 -- the two places on a series page the section links (and the dashboard's in-use card) jump to.
  # Permanent addresses (/products/:slug#episodes may be bookmarked or shared) -- don't rename them.
  SERIES_SECTION_IDS = { intro: "intro", episodes: "episodes" }.freeze

  # Whether each section is on the page at all -- the very conditions that draw them (_info's introduction block,
  # _episode_list's heading and cards), so the section links never point at something that isn't there.
  def series_intro_section?(product_line) = product_line.introduction.present?
  def series_episode_section?(episodes, upcoming_episodes) = episodes.any? || upcoming_episodes.any?

  # Handoff 0092 R3 -- the right side of an episode card on the guide page: [label, badge or nil, locked]. What it says
  # is what the click does -- full access (licensed, or a guide without a commerce product) and 열린 편 open
  # (ProductLineGates#open_preview_episode?, the gate's own check); anything else is stopped by the gate, and the
  # label says what it takes. A member who hasn't started a free guide gets no badge on an 열린 편 (이용하기 is right
  # there); one who hasn't bought a paid guide sees 미리 보기.
  def episode_card_cta(episode, full_access:, signed_in:, free:)
    return [ "보기 →", nil, false ] if full_access

    if open_preview_episode?(episode)
      badge = if !signed_in then "로그인 없이 보기" elsif free then nil else "미리 보기" end
      return [ "보기 →", badge, false ]
    end

    label = if !signed_in then free ? "로그인 후 보기" : "구매 후 보기" else free ? "이용 시작 후 보기" : "구매 후 보기" end
    [ label, nil, true ]
  end

  # Handoff 0092 R3 -- 은/는 after an episode number, by how its last digit is read (일·삼·육·칠·팔·영 end in a
  # consonant -> 은; 이·사·오·구 -> 는): "E01은", "E02는".
  def number_topic_particle(number)
    "136780".include?(number.to_s[-1].to_s) ? "은" : "는"
  end

  # [label, id] for each section on the page, in page order. A third one (리뷰, backlog 0067) would be one more line.
  def series_section_nav_items(product_line, episodes, upcoming_episodes)
    items = []
    items << [ "소개", SERIES_SECTION_IDS[:intro] ] if series_intro_section?(product_line)
    items << [ "에피소드", SERIES_SECTION_IDS[:episodes] ] if series_episode_section?(episodes, upcoming_episodes)
    items
  end

  # Handoff 0096 -- a guide card's episode count on the home: published episodes only; none yet reads 공개 예정.
  # Handoff 0097 -- "에피소드 N" (was "N편"); the home only -- other screens keep their own wording.
  def guide_episode_count_label(published_count)
    published_count.positive? ? "에피소드 #{published_count}" : "공개 예정"
  end

  def product_list_state_classes(state)
    base = "flex-shrink-0 whitespace-nowrap rounded-full border px-3 py-1 text-xs font-bold"
    case state
    when :owned then "#{base} border-accent-soft/40 bg-accent-soft/10 text-accent-ink"
    when :free_open then "#{base} border-ok-soft/40 bg-ok-soft/10 text-ok-ink"
    when :for_sale then "#{base} border-line/20 bg-tint/5 text-ink"
    else "#{base} border-line/10 bg-transparent text-ink-3"
    end
  end
end
