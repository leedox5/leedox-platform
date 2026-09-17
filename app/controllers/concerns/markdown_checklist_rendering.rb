# Redcarpet has no native GFM task-list support -- "- [ ] foo" / "- [x] foo"
# list items render as plain "<li>[ ] foo</li>" text. This turns that into a
# disabled checkbox so it reads as a checklist instead of literal brackets
# (handoff 0054 R2 P1-7). Disabled, not interactive: there's no per-reader
# persistence for check state -- these are copy-into-your-own-notes
# checklists, not a form. Views that render this output must allow <input>
# (type/disabled/checked) and the `style` attribute through `sanitize`.
#
# The generated <li> carries an inline `list-style-type: none` so the
# checkbox doesn't sit next to a leftover bullet dot (HQ operator feedback,
# handoff 0054 R2 follow-up) -- only list items that were actually "- [ ]"/
# "- [x]" get this; ordinary bullet/numbered list items are untouched
# because the regex only ever matches the literal "[ ]"/"[x]" marker Redcarpet
# already emitted for those.
module MarkdownChecklistRendering
  extend ActiveSupport::Concern

  private

  def render_checklist_items(html)
    html.gsub(/<li>\[([ xX])\]\s*/) do
      checked = Regexp.last_match(1).strip.downcase == "x" ? " checked" : ""
      %(<li style="list-style-type: none;"><input type="checkbox" disabled#{checked}> )
    end
  end
end
