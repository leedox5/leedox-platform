class AddTrialChapterLimitToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :trial_chapter_limit, :integer
  end
end
