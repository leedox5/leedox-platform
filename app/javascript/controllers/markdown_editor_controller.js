import { Controller } from "@hotwired/stimulus"

// Handoff 0063 -- editing helpers for a Markdown text field: insert an image
// reference at the cursor, and preview the draft rendered exactly as the
// customer page will (server-side, same ContentMarkdown). The preview HTML is
// produced and sanitized by the server for admins only.
export default class extends Controller {
  static targets = ["textarea", "preview"]
  static values = { url: String, parentType: String, parentId: String }

  async preview() {
    this.previewTarget.hidden = false
    this.previewTarget.innerHTML = '<p class="text-sm text-slate-500">미리보기를 불러오는 중…</p>'

    const body = new URLSearchParams({
      text: this.textareaTarget.value,
      parent_type: this.parentTypeValue,
      parent_id: this.parentIdValue
    })

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
          "Accept": "text/html"
        },
        body
      })
      this.previewTarget.innerHTML = response.ok
        ? await response.text()
        : '<p class="text-sm font-bold text-red-700">미리보기를 만들 수 없습니다. 잠시 후 다시 시도해 주세요.</p>'
    } catch (error) {
      this.previewTarget.innerHTML = '<p class="text-sm font-bold text-red-700">미리보기를 불러오지 못했습니다. 네트워크를 확인해 주세요.</p>'
    }
  }

  closePreview() {
    this.previewTarget.hidden = true
    this.previewTarget.innerHTML = ""
  }

  // Puts the snippet on its own paragraph at the cursor (or replaces the
  // selection) and keeps focus in the text field.
  insert(event) {
    const field = this.textareaTarget
    const snippet = event.params.snippet
    const start = field.selectionStart ?? field.value.length
    const end = field.selectionEnd ?? start
    const before = field.value.slice(0, start)
    const after = field.value.slice(end)
    const lead = before.length === 0 || before.endsWith("\n\n") ? "" : (before.endsWith("\n") ? "\n" : "\n\n")
    const trail = after.length === 0 || after.startsWith("\n\n") ? "" : (after.startsWith("\n") ? "\n" : "\n\n")

    field.setRangeText(lead + snippet + trail, start, end, "end")
    field.focus()
    field.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
