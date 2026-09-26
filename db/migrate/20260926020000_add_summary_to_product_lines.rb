# Handoff 0068 -- a short one-line summary for the customer product list, separate from
# `introduction` (the free-form body). Nullable and unenforced on purpose: existing
# products get no auto-filled value (parsing it out of the introduction was ruled out),
# Tommy fills it in by hand, and the recommended length (~60 chars) is help text, not a
# validation, so a slightly longer line is never rejected.
class AddSummaryToProductLines < ActiveRecord::Migration[8.1]
  def change
    add_column :product_lines, :summary, :string
  end
end
