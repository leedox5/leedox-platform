import { Controller } from "@hotwired/stimulus"

// Shows the chosen file's name next to a styled "choose file" button. The
// real <input type="file"> stays in the DOM (visually hidden, still
// focusable and keyboard-operable), so selection, form submission and
// validation behave exactly as with a plain file input.
export default class extends Controller {
  static targets = ["input", "name"]
  static values = { empty: { type: String, default: "선택된 파일 없음" } }

  connect() {
    this.update()
  }

  update() {
    const file = this.inputTarget.files && this.inputTarget.files[0]
    this.nameTarget.textContent = file ? file.name : this.emptyValue
    this.nameTarget.classList.toggle("font-bold", Boolean(file))
    this.nameTarget.classList.toggle("text-slate-900", Boolean(file))
    this.nameTarget.classList.toggle("text-slate-500", !file)
  }
}
