# Handoff 0065 -- builds data in the LEGACY shape (a Season owns its episodes, a
# Season owns the commerce Product) for the tests of the flattening. Episodes,
# offers and licenses go in with plain inserts / without validation, so this works
# whichever model rules are current. Expects @conn and @line in the test.
module LegacySeasonData
  def season(line, code, slug, status: "published", visibility: "public", position: nil, title: nil, product: nil)
    s = ProductSeason.create!(product_line: line, internal_name: "#{code} 내부", customer_title: title, season_code: code, slug: slug, status: status,
      visibility: visibility, position: position || code[/\d+/].to_i)
    s.update_columns(product_id: product.id) if product
    s
  end

  def product(code, sale: true, amount: 33_000)
    Product.create!(code: code, name: code, active: true, sale_enabled: sale, landing_page_path: "/products/x/#{code}").tap do |p|
      # Without validation: the rule "only a Season/line product may have a one-time offer" depends on links made later.
      ProductOffer.new(product: p, code: "#{code}-once-v1", duration_months: nil, currency: "KRW", active: true, discount_bps: 0, supply_amount: (amount / 1.1).round,
        vat_amount: amount - (amount / 1.1).round, total_amount: amount, version: 1).save!(validate: false)
    end
  end

  def episode(season, position, status: "published", body: "본문 #{position}")
    now = @conn.quote(Time.current)
    @conn.execute("INSERT INTO content_episodes (product_season_id, position, customer_title, body, status, lock_version, created_at, updated_at) " \
                  "VALUES (#{season.id}, #{position}, #{@conn.quote("편 #{position}")}, #{@conn.quote(body)}, #{@conn.quote(status)}, 0, #{now}, #{now})")
    @conn.select_value("SELECT id FROM content_episodes WHERE product_season_id = #{season.id} AND position = #{position}")
  end

  def row(sql) = @conn.select_one(sql)
  def line_of(season) = row("SELECT * FROM product_lines WHERE legacy_season_id = #{season.id}")
end
