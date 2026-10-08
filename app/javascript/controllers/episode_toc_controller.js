import { Controller } from "@hotwired/stimulus"

// Handoff 0105 -- the 길잡이 줄 of a long episode (product_lines/_episode_toc). Shows the bar (it's hidden without
// JavaScript), keeps "N / total · the heading you're reading" and the filling line up to date as the page scrolls,
// and opens / closes the list (the bar, a press outside, Esc). A list item scrolls to its heading -- a scroll, never a
// visit or a history entry, so nothing is fetched or counted as a view.
// The current heading is found like the guide page's section links (0090 section_nav_controller): the last h2 whose
// top has passed a line SLACK px under the bar (a jumped-to h2 lands at its scroll-margin-top, a few px under the
// bar), or the last one once the page can't scroll any further.
const SLACK = 24
const BOTTOM_TOLERANCE = 2

export default class extends Controller {
  static targets = ["button", "list", "counter", "current", "item", "progress"]

  connect() {
    this.element.hidden = false
    this.sections = this.itemTargets
      .filter((item) => item.dataset.sectionId)
      .map((item) => ({ item, heading: document.getElementById(item.dataset.sectionId) }))
      .filter((section) => section.heading)

    this.schedule = this.schedule.bind(this)
    this.closeOnOutside = this.closeOnOutside.bind(this)
    this.closeOnEscape = this.closeOnEscape.bind(this)
    window.addEventListener("scroll", this.schedule, { passive: true })
    window.addEventListener("resize", this.schedule)
    document.addEventListener("click", this.closeOnOutside)
    document.addEventListener("keydown", this.closeOnEscape)
    this.update()
  }

  disconnect() {
    window.removeEventListener("scroll", this.schedule)
    window.removeEventListener("resize", this.schedule)
    document.removeEventListener("click", this.closeOnOutside)
    document.removeEventListener("keydown", this.closeOnEscape)
    if (this.frame) cancelAnimationFrame(this.frame)
  }

  schedule() {
    if (this.frame) return
    this.frame = requestAnimationFrame(() => {
      this.frame = null
      this.update()
    })
  }

  update() {
    const line = this.element.getBoundingClientRect().bottom + SLACK
    let index = -1
    this.sections.forEach((section, i) => {
      if (section.heading.getBoundingClientRect().top <= line) index = i
    })
    const max = document.documentElement.scrollHeight - window.innerHeight
    if (this.sections.length && max > 0 && window.scrollY >= max - BOTTOM_TOLERANCE) index = this.sections.length - 1

    if (index < 0) {
      this.counterTarget.hidden = true
      this.currentTarget.textContent = "목차"
    } else {
      this.counterTarget.hidden = false
      this.counterTarget.textContent = `${index + 1} / ${this.sections.length}`
      this.currentTarget.textContent = this.sections[index].item.textContent.trim()
    }
    this.sections.forEach((section, i) => {
      if (i === index) section.item.setAttribute("aria-current", "true")
      else section.item.removeAttribute("aria-current")
    })

    const ratio = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 0
    this.progressTarget.style.transform = `scaleX(${ratio})`
  }

  toggle() {
    this.setOpen(this.listTarget.hidden)
  }

  setOpen(open) {
    this.listTarget.hidden = !open
    this.buttonTarget.setAttribute("aria-expanded", open ? "true" : "false")
  }

  jump(event) {
    event.preventDefault()
    const id = event.currentTarget.dataset.sectionId
    this.setOpen(false)
    if (id) {
      document.getElementById(id)?.scrollIntoView({ block: "start" })
    } else {
      window.scrollTo({ top: 0 })
    }
  }

  closeOnOutside(event) {
    if (!this.listTarget.hidden && !this.element.contains(event.target)) this.setOpen(false)
  }

  closeOnEscape(event) {
    if (event.key === "Escape" && !this.listTarget.hidden) {
      this.setOpen(false)
      this.buttonTarget.focus()
    }
  }
}
