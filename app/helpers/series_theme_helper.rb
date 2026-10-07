# Handoff 0083 R2 -- the series detail page is dark (the home's palette: #0e1014 page, #15181e cards, #f2efe8 /
# #c9c4ba / #a8a39a text, #f0a53c accent) while the admin preview that shares its partials (_info, _episode_list,
# _episode_card, _upcoming_episode_card) stays exactly as it was. Each entry is [light, dark]; the light value is
# the class string those partials always had, so the admin preview renders the same markup.
#
# The classes live here, in a .rb file, on purpose: Tailwind's scanner drops classes that follow an arbitrary hex
# class inside an ERB Ruby string (0083 R1), but reads Ruby files fine.
module SeriesThemeHelper
  SERIES_THEME = {
    # _info
    name: [ "text-gray-900", "font-display text-ink" ],
    summary: [ "text-slate-600", "text-ink-2" ],
    body: [ "text-gray-700", "text-ink-2" ],
    intro: [ "doc-content", "doc-content doc-content-dark" ],
    # Handoff 0094 A -- the customer page (the dark value) is denser on phones (below sm); sm and up keep the old
    # values, and the admin preview (the light value) is unchanged.
    name_size: [ "text-3xl md:text-4xl", "text-2xl sm:text-3xl md:text-4xl" ],
    summary_size: [ "mt-2 text-lg", "mt-1.5 text-[15px] leading-[23px] sm:mt-2 sm:text-lg sm:leading-7" ],
    body_gap: [ "mt-6", "mt-4 sm:mt-6" ],
    # the gap between the section links and the intro text: 16px on phones -- guide-intro (application.css) also drops
    # the intro's first element's own top margin there (a heading's 32px would otherwise win; 0094 R2).
    intro_gap: [ "mt-11", "guide-intro mt-4 sm:mt-11" ],
    list_gap: [ "space-y-3", "space-y-2 sm:space-y-3" ],
    heading: [ "text-slate-900", "text-ink" ],
    # _purchase_box
    box: [ "border-blue-200 bg-blue-50", "border-line/10 bg-card" ],
    box_rule: [ "border-blue-200", "border-line/10" ], # 0093 -- the rule above the access box inside the header box
    box_title: [ "text-blue-900", "text-ink" ],
    box_text: [ "text-blue-800", "text-ink-2" ],
    box_label: [ "text-blue-700", "text-accent-ink" ],
    box_price: [ "text-slate-950", "text-ink" ],
    box_muted: [ "text-slate-500", "text-ink-3" ],
    box_note: [ "text-slate-600", "text-ink-2" ],
    box_link: [ "text-blue-700 hover:text-blue-800", "text-accent-ink hover:text-accent-ink-hover" ], # 0092 R3 -- the 열린 편 link
    box_closed: [ "text-slate-800", "text-ink" ],
    buy_button: [ "bg-blue-600 text-white shadow-sm hover:bg-blue-700", "bg-accent text-on-accent hover:bg-accent-hover" ],
    free_button: [ "bg-emerald-600 text-white shadow-sm hover:bg-emerald-700", "bg-ok text-on-accent hover:bg-ok-hover" ],
    # _episode_list / cards -- full class strings, so the admin preview's markup stays byte-for-byte the same
    list_heading: [ "mt-8 mb-3 text-2xl font-semibold text-slate-900",
                    "mt-[22px] mb-2.5 text-[21px] font-semibold text-ink sm:mt-8 sm:mb-3 sm:text-2xl" ],
    list_empty: [ "mt-10 text-gray-500", "mt-10 text-ink-3" ],
    card: [ "block rounded-xl border border-gray-200 p-4 hover:border-blue-300",
            "block rounded-xl border border-line/10 bg-card px-3.5 py-[11px] hover:border-accent-soft/60 sm:p-4" ],
    # 0094 A12 / R2 -- customer page: title and 보기 → on one row, top-aligned. On phones the title takes the card's
    # width and wraps between words (no ellipsis); from sm it's one truncated line as before. Any other status moves
    # to the start of the second line on phones (card_meta*), and stays on the title's row from sm.
    card_row: [ "flex flex-wrap items-center gap-x-3 gap-y-1", "flex items-start gap-x-3" ],
    card_title_wrap: [ "min-w-0 flex-1 truncate font-bold text-gray-900",
                       "min-w-0 flex-1 break-keep break-words font-bold leading-[22px] text-ink sm:truncate sm:leading-6" ],
    card_meta: [ "mt-1 truncate text-sm text-gray-500",
                 "mt-1 flex min-w-0 items-center gap-x-1.5 text-[13px] leading-[18px] text-ink-3 sm:text-sm sm:leading-5" ],
    card_meta_status: [ "hidden", "shrink-0 font-semibold text-ink-3 sm:hidden" ],
    upcoming_meta_status: [ "hidden", "shrink-0 font-semibold text-ink-2 sm:hidden" ],
    card_title: [ "min-w-0 flex-1 truncate font-bold text-gray-900", "min-w-0 flex-1 truncate font-bold text-ink" ],
    card_cta: [ "order-last w-full shrink-0 whitespace-nowrap text-sm font-semibold text-blue-600 sm:order-none sm:ml-auto sm:w-auto",
                "ml-auto shrink-0 whitespace-nowrap text-sm font-semibold leading-[22px] text-accent-ink sm:leading-6" ],
    card_summary: [ "mt-1 truncate text-sm text-gray-500", "mt-1 truncate text-sm text-ink-3" ],
    # Handoff 0092 R3 -- a card the viewer can't open yet says why (no arrow, muted), and an 열린 편 carries a small
    # badge (the admin preview's green, on the dark palette).
    card_cta_locked: [ "order-last w-full shrink-0 whitespace-nowrap text-sm font-semibold text-gray-500 sm:order-none sm:ml-auto sm:w-auto",
                       "ml-auto hidden shrink-0 whitespace-nowrap text-sm font-semibold leading-6 text-ink-3 sm:inline" ],
    # 0094 A13 -- on phones the badge moves from the title's line to the start of the teaser line (card_badge_inline).
    card_badge: [ "shrink-0 rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-semibold text-emerald-700",
                  "hidden shrink-0 rounded-full border border-ok-soft/40 bg-ok-soft/10 px-2 py-0.5 text-xs font-semibold text-ok-ink sm:inline-block" ],
    card_badge_inline: [ "hidden",
                         "shrink-0 rounded-full border border-ok-soft/40 bg-ok-soft/10 px-2 py-0.5 text-xs font-semibold text-ok-ink sm:hidden" ],
    card_summary_row: [ "mt-1 truncate text-sm text-gray-500", "mt-1 flex items-center gap-2 text-sm text-ink-3" ],
    # 공개 예정 stays muted by the card's opacity, but on dark it's 70% (not 60%) with brighter text so it still reads
    # at >= 4.5:1 (title 8.0, label/summary 5.55 -- see 0083 result_r2.md).
    # Handoff 0103 -- 80% on the light side (70% there left the label / summary at 4.3:1; 80% gives 9.2 / 5.6).
    upcoming_card: [ "rounded-xl border border-gray-200 p-4 opacity-60", "rounded-xl border border-line/10 bg-card px-3.5 py-[11px] opacity-70 [[data-theme=light]_&]:opacity-80 sm:p-4" ],
    upcoming_title: [ "min-w-0 flex-1 truncate font-semibold text-gray-500",
                      "min-w-0 flex-1 break-keep break-words font-semibold leading-[22px] text-ink sm:truncate sm:leading-6" ],
    upcoming_label: [ "order-last w-full shrink-0 whitespace-nowrap text-sm font-semibold text-gray-400 sm:order-none sm:ml-auto sm:w-auto",
                      "ml-auto hidden shrink-0 whitespace-nowrap text-sm font-semibold leading-6 text-ink-2 sm:inline" ],
    upcoming_summary: [ "mt-1 truncate text-sm text-gray-400",
                        "mt-1 flex min-w-0 items-center gap-x-1.5 text-[13px] leading-[18px] text-ink-2 sm:text-sm sm:leading-5" ]
  }.freeze

  def series_theme(key, dark)
    SERIES_THEME.fetch(key)[dark ? 1 : 0]
  end
end
