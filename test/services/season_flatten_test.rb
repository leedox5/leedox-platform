require "test_helper"
require_relative "../support/legacy_season_data"

# Handoff 0065 -- the lossless move of Season data onto ProductLine (SeasonFlatten).
# Data is built in the *legacy* shape (a Season owns its episodes) with plain
# inserts for the episodes, so this file works whatever the models look like.
class SeasonFlattenTest < ActiveSupport::TestCase
  include LegacySeasonData

  setup do
    @conn = ActiveRecord::Base.connection
    @line = ProductLine.create!(internal_name: "was-core", customer_name: "제품", slug: "flat-line", status: "published",
      introduction: "해결할 문제\n문제 본문", cover_image_alt: "커버", cover_image: { io: file_fixture("covers/cover.jpg").open, filename: "cover.jpg", content_type: "image/jpeg" },
      ai_supporter: "Codex")
  end

  # --- one Season per line (what production looks like) ----------------------

  test "a single Season is absorbed by its line: slug, cover and product stay, the Season title leads the introduction" do
    prod = product("flat_single")
    s = season(@line, "S01", "edition-one", title: "첫 판", product: prod)
    e0 = episode(s, 0)
    episode(s, 1, status: "draft")

    report = SeasonFlatten.run!

    assert report.verified
    mapping = report.mappings.sole
    assert_equal [ @line.id, "flat-line", false, 2 ], [ mapping.line_id, mapping.new_slug, mapping.created, mapping.episodes ]
    line = row("SELECT * FROM product_lines WHERE id = #{@line.id}")
    assert_equal s.id, line["legacy_season_id"]
    assert_equal prod.id, line["product_id"]
    assert_equal "public", line["visibility"]
    assert_equal "published", line["status"]
    assert_nil line["series_key"], "a lone Season is not a series"
    assert_equal "S01", line["series_label"]
    assert_equal "**첫 판**\n\n해결할 문제\n문제 본문", line["introduction"]
    assert @line.reload.cover_image.attached?, "the cover stays where it was"
    assert_equal @line.id, row("SELECT product_line_id FROM content_episodes WHERE id = #{e0}")["product_line_id"]
    assert_equal "/products/flat-line", row("SELECT landing_page_path FROM products WHERE id = #{prod.id}")["landing_page_path"]
    assert_equal 1, @conn.select_value("SELECT COUNT(*) FROM product_seasons").to_i, "the Season table is untouched"
  end

  test "a Season without a title leaves the introduction alone and says so" do
    s = season(@line, "S01", "no-title")
    episode(s, 1)
    report = SeasonFlatten.run!
    assert_equal "해결할 문제\n문제 본문", row("SELECT introduction FROM product_lines WHERE id = #{@line.id}")["introduction"]
    assert(report.warnings.any? { |w| w.include?("no customer title") })
  end

  # --- several Seasons -------------------------------------------------------

  test "later Seasons become their own lines: introduction copied without the first title, no cover, one series" do
    p1 = product("flat_multi_1")
    p2 = product("flat_multi_2", sale: false)
    s1 = season(@line, "S01", "first", title: "첫 판", product: p1)
    s2 = season(@line, "S02", "second", title: "둘째 판", visibility: "unlisted", product: p2)
    s3 = season(@line, "S03", "third", position: 3)
    [ s1, s2, s3 ].each_with_index { |s, i| episode(s, 1, body: "본문 #{i}") }

    report = SeasonFlatten.run!

    assert_equal [ false, true, true ], report.mappings.map(&:created)
    assert_equal %w[flat-line flat-line-second flat-line-third], report.mappings.map(&:new_slug)
    second = line_of(s2)
    assert_equal [ "제품 S02", "S02 내부", "flat-line", "S02", "unlisted", p2.id ],
      second.values_at("customer_name", "internal_name", "series_key", "series_label", "visibility", "product_id")
    assert_equal "**둘째 판**\n\n해결할 문제\n문제 본문", second["introduction"], "copied from the original introduction, with its own Season's title"
    assert_equal "Codex", second["ai_supporter"]
    assert_equal 0, @conn.select_value("SELECT COUNT(*) FROM active_storage_attachments WHERE record_type = 'ProductLine' AND record_id = #{second['id']}").to_i
    assert_equal "flat-line", row("SELECT series_key FROM product_lines WHERE id = #{@line.id}")["series_key"], "the first product joins the series too"
    assert_equal second["id"], row("SELECT product_line_id FROM content_episodes WHERE product_season_id = #{s2.id}")["product_line_id"]
    assert_equal "/products/flat-line-second", row("SELECT landing_page_path FROM products WHERE id = #{p2.id}")["landing_page_path"]
    assert_nil line_of(s3)["product_id"], "a Season with no commerce Product stays free"
  end

  test "a line is published only when both the line and its Season were" do
    published = season(@line, "S01", "pub")
    draft = season(@line, "S02", "drf", status: "draft")
    gone = season(@line, "S03", "gone", status: "unpublished")
    [ published, draft, gone ].each { |s| episode(s, 1) }
    draft_line = ProductLine.create!(internal_name: "d", customer_name: "d", slug: "flat-draft", introduction: "d", status: "draft")
    hidden = season(draft_line, "S01", "hid")
    episode(hidden, 1)

    SeasonFlatten.run!

    assert_equal %w[published draft unpublished], [ published, draft, gone ].map { |s| line_of(s)["status"] }
    assert_equal "draft", line_of(hidden)["status"]
  end

  test "a taken slug gets a numeric suffix and a digits-only Season slug is reported" do
    ProductLine.create!(internal_name: "x", customer_name: "x", slug: "flat-line-second", introduction: "x")
    s1 = season(@line, "S01", "first")
    s2 = season(@line, "S02", "second")
    s3 = season(@line, "S03", "2026")
    [ s1, s2, s3 ].each { |s| episode(s, 1) }

    report = SeasonFlatten.run!

    assert_equal "flat-line-second-2", report.mappings.find { |m| m.old_season_slug == "second" }.new_slug
    assert(report.warnings.any? { |w| w.include?("was taken") })
    assert(report.warnings.any? { |w| w.include?("digits-only") })
  end

  # --- safety ----------------------------------------------------------------

  test "the plan shows exactly what the run does but writes nothing" do
    s1 = season(@line, "S01", "first", title: "첫 판")
    s2 = season(@line, "S02", "second")
    [ s1, s2 ].each { |s| episode(s, 1) }
    lines_before = @conn.select_value("SELECT COUNT(*) FROM product_lines").to_i

    plan = SeasonFlatten.plan
    assert plan.dry_run
    assert plan.verified, "the plan runs the verification too"
    assert_equal lines_before, @conn.select_value("SELECT COUNT(*) FROM product_lines").to_i
    assert_nil row("SELECT legacy_season_id FROM product_lines WHERE id = #{@line.id}")["legacy_season_id"]
    assert_equal 0, @conn.select_value("SELECT COUNT(*) FROM content_episodes WHERE product_line_id IS NOT NULL").to_i

    ran = SeasonFlatten.run!
    assert_equal plan.mappings.map(&:to_a), ran.mappings.map(&:to_a)
    assert_equal lines_before + 1, @conn.select_value("SELECT COUNT(*) FROM product_lines").to_i
  end

  test "running twice changes nothing the second time" do
    s = season(@line, "S01", "first", title: "첫 판")
    episode(s, 1)
    SeasonFlatten.run!
    intro = row("SELECT introduction FROM product_lines WHERE id = #{@line.id}")["introduction"]

    again = SeasonFlatten.run!

    assert_empty again.mappings
    assert_equal intro, row("SELECT introduction FROM product_lines WHERE id = #{@line.id}")["introduction"], "the title is not added a second time"
  end

  test "a Season added after the first run is picked up as a further product" do
    s1 = season(@line, "S01", "first", title: "첫 판")
    episode(s1, 1)
    SeasonFlatten.run!
    s2 = season(@line, "S02", "second", title: "둘째 판")
    episode(s2, 1)

    report = SeasonFlatten.run!

    assert_equal [ "flat-line-second" ], report.mappings.map(&:new_slug)
    assert_equal "**둘째 판**\n\n해결할 문제\n문제 본문", line_of(s2)["introduction"], "the first line's Season title is not copied along"
    assert_equal "flat-line", row("SELECT series_key FROM product_lines WHERE id = #{@line.id}")["series_key"]
  end

  test "a move that would lose data is refused and leaves nothing behind" do
    s = season(@line, "S01", "first")
    id = episode(s, 1, body: "원본 본문")
    original = SeasonFlatten.method(:move_episodes_and_product)
    SeasonFlatten.define_singleton_method(:move_episodes_and_product) do |*args|
      original.call(*args)
      conn.execute("UPDATE content_episodes SET body = 'CORRUPTED' WHERE id = #{id}")
    end

    error = assert_raises(SeasonFlatten::VerificationFailed) { SeasonFlatten.run!(dry_run: false) }
    assert_includes error.message, "episodes"

    assert_equal "원본 본문", row("SELECT body FROM content_episodes WHERE id = #{id}")["body"]
    assert_nil row("SELECT legacy_season_id FROM product_lines WHERE id = #{@line.id}")["legacy_season_id"]
  ensure
    SeasonFlatten.define_singleton_method(:move_episodes_and_product, original)
  end

  test "commerce products, offers and licenses are not touched" do
    prod = product("flat_commerce")
    s = season(@line, "S01", "first", product: prod)
    episode(s, 1)
    user = User.create!(name: "u", email: "flat-u@example.com", password: "password123", created_at: 30.days.ago)
    # Legacy shape: the Product hangs off a Season, not (yet) a line, so the "indefinite only for line products" rule would refuse it.
    License.new(user: user, product: prod, source: "free", status: "active", starts_on: Date.current, last_usable_on: nil, access_ends_at: nil).save!(validate: false)
    licenses = @conn.select_all("SELECT * FROM licenses ORDER BY id").to_a
    offers = @conn.select_all("SELECT * FROM product_offers ORDER BY id").to_a

    SeasonFlatten.run!

    assert_equal licenses, @conn.select_all("SELECT * FROM licenses ORDER BY id").to_a
    assert_equal offers, @conn.select_all("SELECT * FROM product_offers ORDER BY id").to_a
    assert Entitlements::ProductAccess.allowed?(user: user, product_code: prod.code)
  end

  test "verify reports a Season episode that has no product" do
    s = season(@line, "S01", "first")
    episode(s, 1)
    assert_includes SeasonFlatten.verify.join, "no product_line_id"
    SeasonFlatten.run!
    assert_empty SeasonFlatten.verify
  end

  # --- undo -------------------------------------------------------------------

  test "the structure can be undone: clones go, the URL and introduction come back" do
    prod = product("flat_undo")
    s1 = season(@line, "S01", "first", title: "첫 판", product: prod)
    s2 = season(@line, "S02", "second", title: "둘째 판")
    [ s1, s2 ].each { |s| episode(s, 1) }
    SeasonFlatten.run!

    SeasonFlatten.rollback!

    assert_equal 1, @conn.select_value("SELECT COUNT(*) FROM product_lines WHERE slug LIKE 'flat-line%'").to_i
    line = row("SELECT * FROM product_lines WHERE id = #{@line.id}")
    assert_equal "해결할 문제\n문제 본문", line["introduction"]
    assert_nil line["legacy_season_id"]
    assert_nil line["product_id"]
    assert_equal 0, @conn.select_value("SELECT COUNT(*) FROM content_episodes WHERE product_line_id IS NOT NULL").to_i
    assert_equal "/products/flat-line/first", row("SELECT landing_page_path FROM products WHERE id = #{prod.id}")["landing_page_path"]
  end

  test "the undo refuses once a product holds episodes of its own" do
    s = season(@line, "S01", "first")
    episode(s, 1)
    SeasonFlatten.run!
    now = @conn.quote(Time.current)
    @conn.execute("INSERT INTO content_episodes (product_line_id, position, body, status, lock_version, created_at, updated_at) VALUES (#{@line.id}, 5, 'b', 'draft', 0, #{now}, #{now})")

    assert_raises(SeasonFlatten::Blocked) { SeasonFlatten.rollback! }
  end
end
