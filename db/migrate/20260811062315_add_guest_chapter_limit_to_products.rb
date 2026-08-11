# Splits the single trial_chapter_limit column back into two independent
# knobs (handoff 0045 R2) -- it had been quietly driving both the guest gate
# and the trial gate at once, which is why "trial" stopped meaning anything
# once an admin set it (see 0045 result.md). Backfills the new column from
# the old one so behavior is byte-for-byte identical immediately after
# deploy; splitting the two values apart is a deliberate follow-up admin
# action, not something this migration should decide.
class AddGuestChapterLimitToProducts < ActiveRecord::Migration[8.1]
  def up
    add_column :products, :guest_chapter_limit, :integer
    execute "UPDATE products SET guest_chapter_limit = trial_chapter_limit"
  end

  def down
    remove_column :products, :guest_chapter_limit
  end
end
