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
    name: [ "text-gray-900", "font-display text-[#f2efe8]" ],
    summary: [ "text-slate-600", "text-[#c9c4ba]" ],
    body: [ "text-gray-700", "text-[#c9c4ba]" ],
    intro: [ "doc-content", "doc-content doc-content-dark" ],
    heading: [ "text-slate-900", "text-[#f2efe8]" ],
    # _purchase_box
    box: [ "border-blue-200 bg-blue-50", "border-white/10 bg-[#15181e]" ],
    box_rule: [ "border-blue-200", "border-white/10" ], # 0093 -- the rule above the access box inside the header box
    box_title: [ "text-blue-900", "text-[#f2efe8]" ],
    box_text: [ "text-blue-800", "text-[#c9c4ba]" ],
    box_label: [ "text-blue-700", "text-[#f0a53c]" ],
    box_price: [ "text-slate-950", "text-[#f2efe8]" ],
    box_muted: [ "text-slate-500", "text-[#a8a39a]" ],
    box_note: [ "text-slate-600", "text-[#c9c4ba]" ],
    box_link: [ "text-blue-700 hover:text-blue-800", "text-[#f0a53c] hover:text-[#f5b85e]" ], # 0092 R3 -- the 열린 편 link
    box_closed: [ "text-slate-800", "text-[#f2efe8]" ],
    buy_button: [ "bg-blue-600 text-white shadow-sm hover:bg-blue-700", "bg-[#f0a53c] text-[#0e1014] hover:bg-[#f5b85e]" ],
    free_button: [ "bg-emerald-600 text-white shadow-sm hover:bg-emerald-700", "bg-[#7dd3a8] text-[#0e1014] hover:bg-[#9be0bd]" ],
    # _episode_list / cards -- full class strings, so the admin preview's markup stays byte-for-byte the same
    list_heading: [ "mt-8 mb-3 text-2xl font-semibold text-slate-900", "mt-8 mb-3 text-2xl font-semibold text-[#f2efe8]" ],
    list_empty: [ "mt-10 text-gray-500", "mt-10 text-[#a8a39a]" ],
    card: [ "block rounded-xl border border-gray-200 p-4 hover:border-blue-300",
            "block rounded-xl border border-white/10 bg-[#15181e] p-4 hover:border-[#f0a53c]/60" ],
    card_title: [ "min-w-0 flex-1 truncate font-bold text-gray-900", "min-w-0 flex-1 truncate font-bold text-[#f2efe8]" ],
    card_cta: [ "order-last w-full shrink-0 whitespace-nowrap text-sm font-semibold text-blue-600 sm:order-none sm:ml-auto sm:w-auto",
                "order-last w-full shrink-0 whitespace-nowrap text-sm font-semibold text-[#f0a53c] sm:order-none sm:ml-auto sm:w-auto" ],
    card_summary: [ "mt-1 truncate text-sm text-gray-500", "mt-1 truncate text-sm text-[#a8a39a]" ],
    # Handoff 0092 R3 -- a card the viewer can't open yet says why (no arrow, muted), and an 열린 편 carries a small
    # badge (the admin preview's green, on the dark palette).
    card_cta_locked: [ "order-last w-full shrink-0 whitespace-nowrap text-sm font-semibold text-gray-500 sm:order-none sm:ml-auto sm:w-auto",
                       "order-last w-full shrink-0 whitespace-nowrap text-sm font-semibold text-[#a8a39a] sm:order-none sm:ml-auto sm:w-auto" ],
    card_badge: [ "shrink-0 rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-semibold text-emerald-700",
                  "shrink-0 rounded-full border border-[#7dd3a8]/40 bg-[#7dd3a8]/10 px-2 py-0.5 text-xs font-semibold text-[#7dd3a8]" ],
    # 공개 예정 stays muted by the card's opacity, but on dark it's 70% (not 60%) with brighter text so it still reads
    # at >= 4.5:1 (title 8.0, label/summary 5.55 -- see 0083 result_r2.md).
    upcoming_card: [ "rounded-xl border border-gray-200 p-4 opacity-60", "rounded-xl border border-white/10 bg-[#15181e] p-4 opacity-70" ],
    upcoming_title: [ "min-w-0 flex-1 truncate font-semibold text-gray-500", "min-w-0 flex-1 truncate font-semibold text-[#f2efe8]" ],
    upcoming_label: [ "order-last w-full shrink-0 whitespace-nowrap text-sm font-semibold text-gray-400 sm:order-none sm:ml-auto sm:w-auto",
                      "order-last w-full shrink-0 whitespace-nowrap text-sm font-semibold text-[#c9c4ba] sm:order-none sm:ml-auto sm:w-auto" ],
    upcoming_summary: [ "mt-1 truncate text-sm text-gray-400", "mt-1 truncate text-sm text-[#c9c4ba]" ]
  }.freeze

  def series_theme(key, dark)
    SERIES_THEME.fetch(key)[dark ? 1 : 0]
  end
end
