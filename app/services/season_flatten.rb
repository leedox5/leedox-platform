require "digest"

# Handoff 0065 -- moves the data of the Season flattening decided in 0064 (each
# ProductSeason becomes a ProductLine that is the sellable unit) without losing
# anything. Run by hand, after the additive migration
# (20260921140000_add_flattened_product_columns), and checked before it is run:
#
#   bin/rails season_flatten:plan     # runs everything, verifies, then ROLLS BACK
#   bin/rails season_flatten:run      # same, but commits (only if verification passes)
#   bin/rails season_flatten:verify   # re-checks the invariants at any later time
#
# Plain SQL on purpose: it must work while the code that is live is still the
# old (Season-based) one, and it must not depend on the new models.
#
# What it does per ProductLine, seasons taken in `position` order:
#   - the first Season is absorbed by the existing line (slug, cover and
#     introduction stay; product_id / visibility / series_* are filled in);
#   - every later Season becomes a NEW ProductLine (slug "<line>-<season>", name
#     "<name> <S-code>", introduction copied, NO cover -- the operator adds one);
#   - the Season's title is put in front of that line's introduction;
#   - the line's status becomes "published" only if line AND Season were;
#   - the episodes get product_line_id (product_season_id is left alone);
#   - the commerce Product's landing_page_path points at the new URL;
#   - legacy_season_id records where a line came from (redirects, undo).
# Nothing is deleted. It is idempotent: a Season already moved is skipped.
module SeasonFlatten
  class VerificationFailed < StandardError; end
  class Blocked < StandardError; end

  Mapping = Struct.new(:season_id, :season_code, :old_line_slug, :old_season_slug, :line_id, :new_slug, :created, :product_code, :episodes, :status, keyword_init: true)
  Report = Struct.new(:mappings, :warnings, :dry_run, :verified, keyword_init: true)

  NEW_COLUMNS = { "product_lines" => %w[product_id visibility series_key series_label series_position legacy_season_id], "content_episodes" => %w[product_line_id] }.freeze

  module_function

  def conn = ActiveRecord::Base.connection

  def columns_ready?
    NEW_COLUMNS.all? { |table, columns| (columns - conn.columns(table).map(&:name)).empty? }
  end

  # Executes the whole move inside a savepoint and rolls it back, so what is
  # shown is exactly what run! would do, including whether verification passes.
  def plan
    run!(dry_run: true)
  end

  def run!(dry_run: false)
    raise Blocked, "run the migration 20260921140000_add_flattened_product_columns first" unless columns_ready?

    report = Report.new(mappings: [], warnings: [], dry_run: dry_run, verified: false)
    ActiveRecord::Base.transaction(requires_new: true) do
      before = snapshot
      old_visible = old_visible_episode_ids
      move_seasons(report)
      verify!(before, old_visible)
      report.verified = true
      raise ActiveRecord::Rollback if dry_run
    end
    report
  end

  # State-based checks that hold at any time after the move (the Season table is
  # untouched, so the old and the new visibility rule can both be evaluated).
  def verify
    problems = []
    problems << "a Season episode has no product_line_id" if count("SELECT COUNT(*) FROM content_episodes WHERE product_season_id IS NOT NULL AND product_line_id IS NULL").positive?
    problems << "a Product is claimed by more than one line" if conn.select_values("SELECT product_id FROM product_lines WHERE product_id IS NOT NULL GROUP BY product_id HAVING COUNT(*) > 1").any?
    problems << "a Season with a Product is not backed by exactly one line holding that Product" if count(<<~SQL).positive?
      SELECT COUNT(*) FROM product_seasons s WHERE s.product_id IS NOT NULL AND
        (SELECT COUNT(*) FROM product_lines l WHERE l.product_id = s.product_id) <> 1
    SQL
    problems << "the customer-visible episodes differ from the old Season rule" unless old_visible_episode_ids == new_visible_episode_ids
    problems
  end

  # Undoes the structure (not the season-status merge). Refuses when the new
  # code has since created episodes that have no Season to go back to.
  def rollback!
    orphans = count("SELECT COUNT(*) FROM content_episodes WHERE bundle_id IS NULL AND product_season_id IS NULL AND product_line_id IS NOT NULL")
    raise Blocked, "#{orphans} episode(s) were created directly under a product; they cannot go back to a Season" if orphans.positive?

    ActiveRecord::Base.transaction(requires_new: true) do
      conn.select_all("SELECT * FROM product_seasons ORDER BY id").to_a.each do |season|
        line = conn.select_one("SELECT * FROM product_lines WHERE legacy_season_id = #{season['id']}")
        next unless line

        old_line = conn.select_one("SELECT slug FROM product_lines WHERE id = #{season['product_line_id']}")
        if season["product_id"]
          conn.execute("UPDATE products SET landing_page_path = #{q("/products/#{old_line['slug']}/#{season['slug']}")} WHERE id = #{season['product_id']}")
        end
        conn.execute("UPDATE content_episodes SET product_line_id = NULL WHERE product_season_id = #{season['id']}")
        if line["id"] == season["product_line_id"]
          prefix = title_prefix(season)
          intro = line["introduction"].to_s
          intro = intro.delete_prefix(prefix) unless prefix.empty?
          conn.execute("UPDATE product_lines SET introduction = #{q(intro)}, product_id = NULL, visibility = 'public', series_key = NULL, series_label = NULL, series_position = 0, legacy_season_id = NULL WHERE id = #{line['id']}")
        else
          blockers = count("SELECT COUNT(*) FROM content_images WHERE product_line_id = #{line['id']}")
          raise Blocked, "line #{line['slug']} has #{blockers} image(s); remove them before undoing" if blockers.positive?

          conn.execute("DELETE FROM product_lines WHERE id = #{line['id']}")
        end
      end
    end
  end

  # ------------------------------------------------------------------ the move

  def move_seasons(report)
    conn.select_all("SELECT * FROM product_lines ORDER BY id").to_a.each do |line|
      seasons = conn.select_all("SELECT * FROM product_seasons WHERE product_line_id = #{line['id']} ORDER BY position, id").to_a
      next if seasons.empty?

      todo = seasons.reject { |season| conn.select_value("SELECT 1 FROM product_lines WHERE legacy_season_id = #{season['id']}") }
      next if todo.empty?

      absorbed = line["legacy_season_id"].present?
      base_intro = original_introduction(line)
      series_key = seasons.size > 1 ? line["slug"] : nil
      todo.each do |season|
        target_id, slug, created = if absorbed
          clone_line(line, season, base_intro, series_key, report)
        else
          absorbed = true
          absorb_into(line, season, series_key)
        end
        move_episodes_and_product(season, target_id, slug)
        report.warnings << "Season #{line['slug']}/#{season['slug']} has a digits-only slug: its old URL cannot be redirected (it would look like an episode number)" if season["slug"].match?(/\A\d+\z/)
        report.warnings << "Season #{line['slug']}/#{season['slug']} has no customer title: nothing was added to the introduction" if title_prefix(season).empty?
        report.mappings << Mapping.new(
          season_id: season["id"], season_code: season["season_code"], old_line_slug: line["slug"], old_season_slug: season["slug"], line_id: target_id, new_slug: slug,
          created: created, product_code: (season["product_id"] && conn.select_value("SELECT code FROM products WHERE id = #{season['product_id']}")),
          episodes: count("SELECT COUNT(*) FROM content_episodes WHERE product_line_id = #{target_id}"), status: conn.select_value("SELECT status FROM product_lines WHERE id = #{target_id}")
        )
      end
      # a line that gained a sibling Season after it was moved becomes a series member too
      conn.execute("UPDATE product_lines SET series_key = #{q(line['slug'])} WHERE id = #{line['id']} AND series_key IS NULL") if series_key
    end
  end

  def absorb_into(line, season, series_key)
    intro = "#{title_prefix(season)}#{line['introduction']}"
    conn.execute(<<~SQL)
      UPDATE product_lines SET introduction = #{q(intro)}, status = #{q(merged_status(line, season))}, visibility = #{q(season['visibility'])},
        product_id = #{n(season['product_id'])}, series_key = #{q(series_key)}, series_label = #{q(season['season_code'])},
        series_position = #{season['position'].to_i}, legacy_season_id = #{season['id']}, updated_at = #{q(Time.current)}
      WHERE id = #{line['id']}
    SQL
    [ line["id"], line["slug"], false ]
  end

  def clone_line(line, season, base_intro, series_key, report)
    slug = unique_slug("#{line['slug']}-#{season['slug']}", report)
    now = q(Time.current)
    conn.execute(<<~SQL)
      INSERT INTO product_lines (internal_name, customer_name, slug, status, introduction, ai_supporter, visibility, product_id,
                                 series_key, series_label, series_position, legacy_season_id, created_at, updated_at)
      VALUES (#{q(season['internal_name'])}, #{q([ line['customer_name'], season['season_code'] ].join(' '))}, #{q(slug)}, #{q(merged_status(line, season))},
              #{q("#{title_prefix(season)}#{base_intro}")}, #{q(line['ai_supporter'])}, #{q(season['visibility'])}, #{n(season['product_id'])},
              #{q(series_key)}, #{q(season['season_code'])}, #{season['position'].to_i}, #{season['id']}, #{now}, #{now})
    SQL
    [ conn.select_value("SELECT id FROM product_lines WHERE slug = #{q(slug)}"), slug, true ]
  end

  def move_episodes_and_product(season, line_id, slug)
    conn.execute("UPDATE content_episodes SET product_line_id = #{line_id} WHERE product_season_id = #{season['id']}")
    return unless season["product_id"]

    conn.execute("UPDATE products SET landing_page_path = #{q("/products/#{slug}")} WHERE id = #{season['product_id']}")
  end

  # The introduction the line had before its own Season title was put in front.
  def original_introduction(line)
    return line["introduction"].to_s if line["legacy_season_id"].blank?

    season = conn.select_one("SELECT * FROM product_seasons WHERE id = #{line['legacy_season_id']}")
    prefix = season ? title_prefix(season) : ""
    line["introduction"].to_s.delete_prefix(prefix)
  end

  def title_prefix(season)
    title = season["customer_title"].to_s.strip
    title.empty? ? "" : "**#{title}**\n\n"
  end

  # Customers saw a Season only when both it and its line were published.
  def merged_status(line, season)
    return "published" if line["status"] == "published" && season["status"] == "published"

    [ line["status"], season["status"] ].include?("unpublished") ? "unpublished" : "draft"
  end

  def unique_slug(base, report)
    slug = base
    suffix = 1
    while conn.select_value("SELECT 1 FROM product_lines WHERE slug = #{q(slug)}")
      suffix += 1
      slug = "#{base}-#{suffix}"
    end
    report.warnings << "slug #{base} was taken, used #{slug}" unless slug == base
    slug
  end

  # ------------------------------------------------------------- verification

  def snapshot
    children = %w[content_revisions content_takeaways content_assets content_images].select { |t| conn.table_exists?(t) }
    {
      episodes: digest("SELECT id, position, customer_title, body, status, lock_version FROM content_episodes ORDER BY id"),
      children: children.to_h { |t| [ t, count("SELECT COUNT(*) FROM #{t}") ] },
      attachments: digest("SELECT record_type, record_id, name, blob_id FROM active_storage_attachments ORDER BY id"),
      products: digest("SELECT id, code, name, active, sale_enabled FROM products ORDER BY id"),
      offers: digest("SELECT * FROM product_offers ORDER BY id"),
      licenses: digest("SELECT id, user_id, product_id, status, source, access_ends_at, last_usable_on FROM licenses ORDER BY id"),
      audit: count("SELECT COUNT(*) FROM commerce_audit_events"),
      seasons: digest("SELECT * FROM product_seasons ORDER BY id")
    }
  end

  def verify!(before, old_visible)
    after = snapshot
    labels = { episodes: "episodes", children: "revisions/takeaways/assets/images", attachments: "attached files", products: "commerce products", offers: "offers",
               licenses: "licenses", audit: "audit events", seasons: "the Season table (must stay untouched)" }
    changed = before.keys.reject { |key| before[key] == after[key] }.map { |key| labels[key] }
    changed.concat(verify)
    raise VerificationFailed, "not lossless: #{changed.join('; ')}" if changed.any?
    raise VerificationFailed, "visible episodes changed" unless old_visible == new_visible_episode_ids
  end

  def old_visible_episode_ids
    conn.select_values(<<~SQL).map(&:to_i).sort
      SELECT e.id FROM content_episodes e JOIN product_seasons s ON s.id = e.product_season_id JOIN product_lines l ON l.id = s.product_line_id
      WHERE l.status = 'published' AND s.status = 'published' AND s.visibility IN ('public', 'unlisted') AND e.status = 'published'
    SQL
  end

  def new_visible_episode_ids
    conn.select_values(<<~SQL).map(&:to_i).sort
      SELECT e.id FROM content_episodes e JOIN product_lines l ON l.id = e.product_line_id
      WHERE e.product_season_id IS NOT NULL AND l.status = 'published' AND l.visibility IN ('public', 'unlisted') AND e.status = 'published'
    SQL
  end

  # ---------------------------------------------------------------- helpers

  def count(sql) = conn.select_value(sql).to_i
  def digest(sql) = Digest::MD5.hexdigest(conn.select_all(sql).to_a.to_json)
  def q(value) = conn.quote(value)
  def n(value) = value.nil? ? "NULL" : value.to_i
end
