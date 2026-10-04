# Handoff 0084 (D-010) -- the frame (header, mobile menu panel, footer) is dark on every customer page and light on
# the screens only admins use. Each entry is [light, dark]; the light value is the class string the header always had.
#
# The classes live here, in a .rb file, on purpose: Tailwind's scanner drops classes that follow an arbitrary hex class
# inside an ERB Ruby string (0083), and that is how the dark header's own background (`bg-[#0e1014]/90`) was never
# built -- the header has been transparent since 0071. test/assets/tailwind_build_test.rb builds the CSS and checks
# every class here (and in the other theme tables) is actually in it.
module FrameThemeHelper
  # Admin-only screens outside the Admin:: namespace (D-010: "admin" means who uses it, not the URL).
  ADMIN_ONLY_CONTROLLERS = %w[service_desk service_desk_jobs refs].freeze

  FRAME_THEME = {
    header: [ "border-slate-200/70 bg-white/90 shadow-sm", "border-white/10 bg-[#0e1014]/90" ],
    logo: [ "text-slate-950", "text-[#f2efe8]" ],
    logo_mark: [ "bg-slate-950 text-white group-hover:bg-indigo-700", "bg-[#f0a53c] text-[#0e1014]" ],
    nav: [ "text-slate-600", "text-[#c9c4ba]" ],
    nav_link: [ "hover:text-slate-950", "hover:text-[#f2efe8]" ],
    user_name: [ "text-slate-500", "text-[#a8a39a]" ],
    logout: [ "rounded-lg border border-red-200 px-4 py-2 text-red-600 transition hover:border-red-300 hover:bg-red-50",
              "rounded-lg border border-white/25 px-4 py-2 text-[#f2efe8] transition hover:border-white/50" ],
    login: [ "rounded-lg border border-slate-200 px-4 py-2 text-slate-700 transition hover:border-slate-300 hover:text-slate-900",
             "rounded-lg border border-white/25 px-4 py-2 text-[#f2efe8] transition hover:border-white/50" ],
    signup: [ "rounded-lg bg-blue-600 px-4 py-2 font-semibold text-white transition hover:bg-blue-700",
              "rounded-lg bg-[#f0a53c] px-4 py-2 font-semibold text-[#0e1014] transition hover:bg-[#f5b85e]" ],
    menu_button: [ "border-slate-200 text-slate-700 hover:bg-slate-50", "border-white/25 text-[#f2efe8] hover:bg-white/10" ],
    panel: [ "border-slate-200 bg-white", "border-white/10 bg-[#15181e]" ],
    panel_link: [ "text-slate-700 hover:bg-slate-50 hover:text-slate-950", "text-[#c9c4ba] hover:bg-white/5 hover:text-[#f2efe8]" ],
    panel_divider: [ "border-slate-100", "border-white/10" ],
    panel_name: [ "text-slate-500", "text-[#a8a39a]" ],
    panel_logout: [ "text-red-600 hover:bg-red-50", "text-[#f0a53c] hover:bg-white/5" ],
    panel_login: [ "border-slate-200 text-slate-700 hover:bg-slate-50", "border-white/25 text-[#f2efe8] hover:border-white/50" ],
    panel_signup: [ "bg-blue-600 text-white hover:bg-blue-700", "bg-[#f0a53c] text-[#0e1014] hover:bg-[#f5b85e]" ]
  }.freeze

  # The footer is only used on customer pages, so it is always dark; its link class sits here for the same reason.
  FOOTER_LINK_CLASS = "transition hover:text-[#f2efe8]".freeze

  def frame_theme(key, dark)
    FRAME_THEME.fetch(key)[dark ? 1 : 0]
  end

  # The default for the header's `dark:` -- dark everywhere but the admin area (Admin::) and the admin-only screens above.
  def dark_frame?
    !controller_path.start_with?("admin/") && !ADMIN_ONLY_CONTROLLERS.include?(controller_path)
  end
end
