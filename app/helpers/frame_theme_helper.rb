# Handoff 0084 (D-010) -- the frame (header, mobile menu panel, footer) is dark on every customer page and light on
# the screens only admins use. Each entry is [light, dark]; the light value is the class string the header always had.
#
# The classes live here, in a .rb file, on purpose: Tailwind's scanner drops classes that follow an arbitrary hex class
# inside an ERB Ruby string (0083), and that is how the dark header's own background (`bg-page/90`) was never
# built -- the header has been transparent since 0071. test/assets/tailwind_build_test.rb builds the CSS and checks
# every class here (and in the other theme tables) is actually in it.
module FrameThemeHelper
  # Admin-only screens outside the Admin:: namespace (D-010: "admin" means who uses it, not the URL).
  ADMIN_ONLY_CONTROLLERS = %w[service_desk service_desk_jobs refs].freeze

  FRAME_THEME = {
    header: [ "border-slate-200/70 bg-white/90 shadow-sm", "border-line/10 bg-page/90" ],
    logo: [ "text-slate-950", "text-ink" ],
    logo_mark: [ "bg-slate-950 text-white group-hover:bg-indigo-700", "bg-accent text-on-accent" ],
    nav: [ "text-slate-600", "text-ink-2" ],
    nav_link: [ "hover:text-slate-950", "hover:text-ink" ],
    user_name: [ "text-slate-500", "text-ink-3" ],
    logout: [ "rounded-lg border border-red-200 px-4 py-2 text-red-600 transition hover:border-red-300 hover:bg-red-50",
              "rounded-lg border border-line/25 px-4 py-2 text-ink transition hover:border-line/50" ],
    login: [ "rounded-lg border border-slate-200 px-4 py-2 text-slate-700 transition hover:border-slate-300 hover:text-slate-900",
             "rounded-lg border border-line/25 px-4 py-2 text-ink transition hover:border-line/50" ],
    signup: [ "rounded-lg bg-blue-600 px-4 py-2 font-semibold text-white transition hover:bg-blue-700",
              "rounded-lg bg-accent px-4 py-2 font-semibold text-on-accent transition hover:bg-accent-hover" ],
    menu_button: [ "border-slate-200 text-slate-700 hover:bg-slate-50", "border-line/25 text-ink hover:bg-tint/10" ],
    panel: [ "border-slate-200 bg-white", "border-line/10 bg-card" ],
    panel_link: [ "text-slate-700 hover:bg-slate-50 hover:text-slate-950", "text-ink-2 hover:bg-tint/5 hover:text-ink" ],
    panel_divider: [ "border-slate-100", "border-line/10" ],
    panel_name: [ "text-slate-500", "text-ink-3" ],
    panel_logout: [ "text-red-600 hover:bg-red-50", "text-accent-ink hover:bg-tint/5" ],
    panel_login: [ "border-slate-200 text-slate-700 hover:bg-slate-50", "border-line/25 text-ink hover:border-line/50" ],
    panel_signup: [ "bg-blue-600 text-white hover:bg-blue-700", "bg-accent text-on-accent hover:bg-accent-hover" ]
  }.freeze

  # The footer is only used on customer pages, so it is always dark; its link class sits here for the same reason.
  FOOTER_LINK_CLASS = "transition hover:text-ink".freeze

  def frame_theme(key, dark)
    FRAME_THEME.fetch(key)[dark ? 1 : 0]
  end

  # The default for the header's `dark:` -- dark everywhere but the admin area (Admin::) and the admin-only screens above.
  def dark_frame?
    !controller_path.start_with?("admin/") && !ADMIN_ONLY_CONTROLLERS.include?(controller_path)
  end

  # Handoff 0100 -- the <body> classes. A page whose body is dark from edge to edge (home, /about, /products, a guide,
  # an episode, the dashboard) says `content_for :color_scheme, "dark"`: the layout then adds
  # <meta name="color-scheme" content="dark"> and this dark body, so the browser knows the page is dark (scrollbars,
  # the canvas shown when the page is pulled past its ends or is shorter than the window, a browser's own dark mode).
  # Per page, not per controller (/products/:slug/continue is light). Every other page keeps the body it always had.
  # The text color stays text-slate-900: every dark page sets its own on its outer wrapper.
  # Both live on <head> meta and <body>, which Turbo swaps per page (meta is a provisional head element; the body is
  # replaced) -- unlike <html>'s attributes, which it keeps across visits.
  BODY_CLASS = {
    light: "bg-slate-50 text-slate-900 antialiased",
    dark: "bg-page text-slate-900 antialiased [color-scheme:dark]"
  }.freeze

  def dark_page?
    content_for(:color_scheme) == "dark"
  end

  def body_class
    BODY_CLASS.fetch(dark_page? ? :dark : :light)
  end
end
