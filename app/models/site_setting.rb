# Handoff 0097 -- small site-wide values the operator edits in the admin (no settings store existed before). One row
# per key; only the home's featured-section title for now.
class SiteSetting < ApplicationRecord
  HOME_FEATURED_TITLE = "home_featured_title"
  HOME_FEATURED_TITLE_DEFAULT = "지금 시작하는 가이드"
  HOME_FEATURED_TITLE_MAX = 30 # ~13 characters a line at 24px on a phone -- two lines at most

  validates :key, presence: true, uniqueness: true
  validates :value, length: { maximum: HOME_FEATURED_TITLE_MAX }, if: -> { key == HOME_FEATURED_TITLE }

  # The title as the home shows it -- the default when blank. The rescue covers the deploy window before the 0097
  # migration has created this table, so the home never fails over its heading.
  def self.home_featured_title
    find_by(key: HOME_FEATURED_TITLE)&.value.presence || HOME_FEATURED_TITLE_DEFAULT
  rescue ActiveRecord::StatementInvalid
    HOME_FEATURED_TITLE_DEFAULT
  end

  # What the operator typed, or "" when nothing is stored (the form shows the default as its placeholder).
  def self.home_featured_title_input
    find_by(key: HOME_FEATURED_TITLE)&.value.to_s
  end

  # Line breaks and runs of spaces become one space (the title is one plain line; the view escapes it).
  # Returns the record, with errors when it didn't save.
  def self.save_home_featured_title(value)
    setting = find_or_initialize_by(key: HOME_FEATURED_TITLE)
    setting.value = value.to_s.squish.presence
    setting.save
    setting
  end
end
