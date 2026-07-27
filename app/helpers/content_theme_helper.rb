# Tailwind's static scanner only picks up classes that appear as complete,
# literal strings somewhere in the source -- "bg-#{accent}-600" via string
# interpolation is invisible to it, so the style silently never ships. This
# hash is the one place accent -> literal Tailwind classes are spelled out in
# full, so every class this helper can return already appears verbatim here.
module ContentThemeHelper
  ACCENT_CLASSES = {
    "blue" => {
      label: "text-blue-600",
      icon_badge: "bg-blue-50 text-blue-600",
      icon_badge_hover: "group-hover:bg-blue-100",
      link_hover_border: "hover:border-blue-200",
      link_hover_text: "group-hover:text-blue-600",
      link_hover_arrow: "group-hover:text-blue-400",
      nav_hover: "hover:text-blue-600",
      sidebar_current: "bg-blue-50 font-semibold text-blue-700",
      sidebar_current_badge: "bg-blue-600 text-white"
    },
    "violet" => {
      label: "text-violet-600",
      icon_badge: "bg-violet-50 text-violet-600",
      icon_badge_hover: "group-hover:bg-violet-100",
      link_hover_border: "hover:border-violet-200",
      link_hover_text: "group-hover:text-violet-600",
      link_hover_arrow: "group-hover:text-violet-400",
      nav_hover: "hover:text-violet-600",
      sidebar_current: "bg-violet-50 font-semibold text-violet-700",
      sidebar_current_badge: "bg-violet-600 text-white"
    },
    "emerald" => {
      label: "text-emerald-600",
      icon_badge: "bg-emerald-50 text-emerald-600",
      icon_badge_hover: "group-hover:bg-emerald-100",
      link_hover_border: "hover:border-emerald-200",
      link_hover_text: "group-hover:text-emerald-600",
      link_hover_arrow: "group-hover:text-emerald-400",
      nav_hover: "hover:text-emerald-600",
      sidebar_current: "bg-emerald-50 font-semibold text-emerald-700",
      sidebar_current_badge: "bg-emerald-600 text-white"
    }
  }.freeze

  def content_theme_classes(accent)
    ACCENT_CLASSES.fetch(accent, ACCENT_CLASSES.fetch("blue"))
  end
end
