import { Controller } from "@hotwired/stimulus"

// Handoff 0090 -- marks the series-page section in view (소개 / 에피소드) on the sticky section links with
// aria-current="true" (the CSS styles it). The links are plain #anchors and work without this.
// The current section is the last one whose top has scrolled past the bottom of the sticky bars -- or, once the
// page can't scroll any further, the last section (R2): a short last section never reaches that line, so after
// jumping to it the bar would otherwise keep showing the one before. Works the same with a third item (리뷰).
//
// SLACK: a jumped-to section lands at its scroll-margin-top (112px, scroll-mt-28) -- 5~7px below the bars (107px
// mobile / 105px from md up, measured by HQ). The line sits 24px under the bars so that landing always counts as
// "reached", with room for font and rounding differences.
const SLACK = 24
const BOTTOM_TOLERANCE = 2

export default class extends Controller {
  static targets = ["link"]

  connect() {
    this.update = this.update.bind(this)
    window.addEventListener("scroll", this.update, { passive: true })
    window.addEventListener("resize", this.update)
    this.update()
  }

  disconnect() {
    window.removeEventListener("scroll", this.update)
    window.removeEventListener("resize", this.update)
  }

  update() {
    const line = this.element.getBoundingClientRect().bottom + SLACK
    let current = this.linkTargets[0]
    for (const link of this.linkTargets) {
      const section = document.getElementById(link.hash.slice(1))
      if (section && section.getBoundingClientRect().top <= line) current = link
    }
    if (this.atBottom()) current = this.linkTargets[this.linkTargets.length - 1]
    for (const link of this.linkTargets) {
      if (link === current) link.setAttribute("aria-current", "true")
      else link.removeAttribute("aria-current")
    }
  }

  // Scrolled as far down as the page goes (and the page scrolls at all -- a page that fits the window stays on
  // the position rule).
  atBottom() {
    const doc = document.documentElement
    const scrollable = doc.scrollHeight > window.innerHeight + BOTTOM_TOLERANCE
    return scrollable && window.innerHeight + window.scrollY >= doc.scrollHeight - BOTTOM_TOLERANCE
  }
}
