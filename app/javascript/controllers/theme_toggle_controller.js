import { Controller } from "@hotwired/stimulus"

// Handoff 0103 (D-014 step 3) -- the header's dark / light switch (shared/_theme_toggle). A press switches the page in
// place -- no visit, so the scroll position, open <details> and a half-written comment stay -- and remembers the
// choice in the same cookie the server reads (0102: leedox_theme, a year, Lax), so every later page is drawn in that
// mode from the start. What changes, in order: the cookie; <body data-theme>; on the six dark pages the
// color-scheme class on <body> and the color-scheme meta; the theme-color meta; every switch's name and link. The icon
// follows <body data-theme> by itself (CSS). Pages Turbo or the browser kept from before the switch are brought in
// line when they come back (back / forward), and Turbo's snapshots are dropped.
// FrameThemeHelper keeps the same names and colors for the server side.
const COOKIE = "leedox_theme"
const LABELS = { dark: "밝게 보기", light: "어둡게 보기" }
const THEME_COLORS = { dark: "#0e1014", light: "#f5f2ea" }
const SCHEME_CLASSES = { dark: "[color-scheme:dark]", light: "[color-scheme:light]" }

function cookieTheme() {
  const match = document.cookie.match(/(?:^|;\s*)leedox_theme=([^;]*)/)
  return match && match[1] === "light" ? "light" : "dark"
}

function pageTheme() {
  return document.body.dataset.theme === "light" ? "light" : "dark"
}

function rememberTheme(theme) {
  const secure = location.protocol === "https:" ? "; secure" : ""
  document.cookie = `${COOKIE}=${theme}; path=/; max-age=31536000; samesite=lax${secure}`
}

// Only pages that carry the switch (customer pages) are ever touched -- the admin screens stay as they are.
function applyTheme(theme) {
  const body = document.body
  if (!document.querySelector("[data-theme-toggle]")) return

  if (theme === "light") {
    body.dataset.theme = "light"
  } else {
    delete body.dataset.theme
  }
  const other = theme === "light" ? "dark" : "light"
  if (body.classList.contains(SCHEME_CLASSES[other])) body.classList.replace(SCHEME_CLASSES[other], SCHEME_CLASSES[theme])
  const scheme = document.head.querySelector('meta[name="color-scheme"]')
  if (scheme) scheme.content = theme
  const bar = document.head.querySelector('meta[name="theme-color"]')
  if (bar) bar.content = THEME_COLORS[theme]

  document.querySelectorAll("[data-theme-toggle]").forEach((toggle) => {
    toggle.setAttribute("aria-label", LABELS[theme])
    toggle.setAttribute("title", LABELS[theme])
    const url = new URL(toggle.getAttribute("href"), location.href)
    url.searchParams.set("theme", other)
    toggle.setAttribute("href", url.pathname + url.search)
  })
}

function syncWithCookie() {
  const theme = cookieTheme()
  if (theme !== pageTheme()) applyTheme(theme)
}

// A page the browser restores from its back / forward cache, or one Turbo shows from its snapshot cache, was drawn
// before the last switch -- bring it in line with the cookie.
window.addEventListener("pageshow", (event) => { if (event.persisted) syncWithCookie() })
document.addEventListener("turbo:render", syncWithCookie)

export default class extends Controller {
  toggle(event) {
    event.preventDefault()
    const theme = pageTheme() === "light" ? "dark" : "light"
    rememberTheme(theme)
    applyTheme(theme)
    window.Turbo?.cache?.clear?.()
  }
}
