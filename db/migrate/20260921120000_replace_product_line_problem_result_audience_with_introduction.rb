# Handoff 0060 -- ProductLine's three fixed fields (problem / expected_result /
# target_audience) are replaced by one free-form `introduction`.
#
# The three old columns are NOT dropped here: they stay, nullable and no longer
# read or written by the app, so the merged draft can be checked against the
# originals on production and a later handoff can drop them. Dropping them in
# the same one-shot manual production migration would make a mistake in the
# merge unrecoverable (a rollback re-creates empty columns, not the data).
class ReplaceProductLineProblemResultAudienceWithIntroduction < ActiveRecord::Migration[8.1]
  # Migration-local model so the backfill does not depend on ProductLine's
  # validations/callbacks, which change with this same handoff.
  class MigrationProductLine < ActiveRecord::Base
    self.table_name = "product_lines"
  end

  HEADINGS = [ "해결할 문제", "기대 결과", "대상 고객" ].freeze

  # Keeps each old value under its old heading, in the old order, skipping blank
  # ones: nothing is lost, and a live product page reads the same until an admin
  # rewrites it.
  def self.merged_draft(problem, expected_result, target_audience)
    HEADINGS.zip([ problem, expected_result, target_audience ]).filter_map do |heading, value|
      value = value.to_s.strip
      "#{heading}\n#{value}" if value.present?
    end.join("\n\n")
  end

  def up
    add_column :product_lines, :introduction, :text, null: false, default: ""

    MigrationProductLine.reset_column_information
    MigrationProductLine.find_each do |line|
      line.update_columns(introduction: self.class.merged_draft(line.problem, line.expected_result, line.target_audience))
    end

    change_column_null :product_lines, :problem, true
    change_column_null :product_lines, :expected_result, true
    change_column_null :product_lines, :target_audience, true
  end

  def down
    MigrationProductLine.reset_column_information
    # Rows written after the up-migration have nil old columns: keep their
    # introduction (in `problem`) rather than losing it, then restore NOT NULL.
    MigrationProductLine.where(problem: nil).find_each { |line| line.update_columns(problem: line.introduction.to_s) }
    MigrationProductLine.where(expected_result: nil).update_all(expected_result: "")
    MigrationProductLine.where(target_audience: nil).update_all(target_audience: "")

    change_column_null :product_lines, :problem, false
    change_column_null :product_lines, :expected_result, false
    change_column_null :product_lines, :target_audience, false
    remove_column :product_lines, :introduction
  end
end
