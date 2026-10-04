# Handoff 0077 -- notices (공지) readable by everyone, written by admins. Deliberately its own
# table with no link to service_desk_requests: that code assumes admin-only readers, and mixing
# a public audience into it is how internal tickets would leak (0076).
class CreateAnnouncements < ActiveRecord::Migration[8.1]
  def change
    create_table :announcements do |t|
      t.string :title, null: false, limit: 100
      t.text :body, null: false
      t.boolean :published, null: false, default: false
      t.datetime :published_at
      t.boolean :pinned, null: false, default: false
      t.timestamps
    end
    add_index :announcements, %i[published published_at]
    # At most one pinned notice (the one the home may show), backed up at the database level --
    # same pattern as product_lines.featured (0071).
    add_index :announcements, :pinned, unique: true, where: "pinned", name: "index_announcements_on_pinned_only_one"
  end
end
