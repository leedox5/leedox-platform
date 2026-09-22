require "test_helper"
require_relative "../support/legacy_season_data"

# Handoff 0065 -- needs the NEW ProductLine model (acquirable?, customer_reachable),
# so it ships with the new code, not with the additive first step.
class SeasonFlattenParityTest < ActiveSupport::TestCase
  include LegacySeasonData

  setup do
    @conn = ActiveRecord::Base.connection
    @line = ProductLine.create!(internal_name: "was-core", customer_name: "제품", slug: "flat-line", status: "published", introduction: "해결할 문제\n문제 본문")
  end

  # The price summary of handoff 0059 read "which Seasons can a visitor get right now, and for how much".
  # That question is answered by ProductLine#acquirable? now; it must give the very same answer.
  test "what a visitor can get, and for how much, is identical before and after the move" do
    previous = ENV["LEEDOX_COMMERCE_ENABLED"]
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    paid = season(@line, "S01", "paid", product: product("flat_paid", amount: 33_000))
    free = season(@line, "S02", "free", product: product("flat_free", amount: 0), visibility: "unlisted")
    stopped = season(@line, "S03", "stopped", product: product("flat_stopped", sale: false, amount: 29_000))
    season(@line, "S04", "unpriced")
    season(@line, "S05", "hidden", product: product("flat_hidden", amount: 10_000), visibility: "private")
    draft = season(@line, "S06", "draft-one", status: "draft", product: product("flat_draft", amount: 20_000))
    [ paid, free, stopped, draft ].each { |s| episode(s, 1) }

    old_rule = @conn.select_all(<<~SQL).map { |r| [ r["ss"], r["price"] ] }.sort
      SELECT s.slug ss, o.total_amount price FROM product_seasons s JOIN product_lines l ON l.id = s.product_line_id JOIN products p ON p.id = s.product_id
      JOIN product_offers o ON o.product_id = p.id AND o.duration_months IS NULL
      WHERE s.status = 'published' AND s.visibility IN ('public', 'unlisted') AND l.status = 'published' AND o.active = #{@conn.quoted_true} AND p.active = #{@conn.quoted_true} AND p.sale_enabled = #{@conn.quoted_true}
    SQL
    assert_equal [ [ "free", 0 ], [ "paid", 33_000 ] ], old_rule

    SeasonFlatten.run!

    # as the old page did: first what a visitor may open (reachable), then what they can get
    new_rule = ProductLine.customer_reachable.where.not(legacy_season_id: nil).select(&:acquirable?).map do |line|
      [ row("SELECT slug FROM product_seasons WHERE id = #{line.legacy_season_id}")["slug"], line.price ]
    end.sort
    assert_equal old_rule, new_rule
    assert_equal 33_000, line_of(paid).then { |l| ProductLine.find(l["id"]).price }
  ensure
    previous.nil? ? ENV.delete("LEEDOX_COMMERCE_ENABLED") : ENV["LEEDOX_COMMERCE_ENABLED"] = previous
  end
end
