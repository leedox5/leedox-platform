require "test_helper"
require_relative "../../support/content_snapshot_fixture"

class ProductContent::ChatdoxSeasonedSourceTest < ActiveSupport::TestCase
  include ContentSnapshotFixture

  test "preserves S01 chapter order titles phases and access boundaries with canonical identity" do
    with_parity_snapshot do |root|
      source = seasoned(root)

      assert source.usable?
      assert_equal 20, source.public_chapters.length
      assert_equal ProductContent::ChatdoxLegacySource::CHAPTERS.pluck(:title), source.public_chapters.pluck(:title)
      assert_equal (1..20).map { |number| format("S01E%02d", number) }, source.public_chapters.pluck(:id)
      assert_equal %i[guest guest trial trial trial], source.public_chapters.first(5).pluck(:access_tier)
      assert source.public_chapters.drop(5).all? { |chapter| chapter[:access_tier] == :license }
      assert_equal ProductContent::ChatdoxLegacySource::PHASES.pluck(:key), source.phases.pluck(:key)
    end
  end

  test "provides canonical and explicit compatibility lookups without changing internal identity" do
    with_parity_snapshot do |root|
      source = seasoned(root)
      adapter = ProductContent::ChatdoxSeasonedCompatibilityAdapter.new("chatdox", snapshot_path: root)

      assert_equal "S01E01", source.find("S01E01")[:id]
      assert_nil source.find("01")
      assert_equal "S01E01", source.legacy_s01_lookup("1")[:id]
      assert_equal "S01E01", source.find_by(season_code: "s01", episode_number: 1)[:id]
      assert_equal "01", adapter.find("1")[:id]
      assert_equal "S01E01", adapter.find("1")[:canonical_id]
      assert_equal 2, adapter.guest_chapter_limit
      assert_equal 5, adapter.trial_chapter_limit
      assert_equal [ 1..5, 6..16, 17..20 ], adapter.phases.pluck(:range)
    end
  end

  test "hides upcoming S02 review and draft from public and direct lookup but exposes admin metadata" do
    with_parity_snapshot do |root|
      source = seasoned(root)

      assert_equal({ "s01" => 20, "s02" => 0 }, source.seasons.to_h { |season| [ season[:code], season[:public_episode_count] ] })
      assert_nil source.find("S02E01")
      assert_nil source.find_direct("S02E01")
      assert_equal :review, source.find_for_admin("S02E01")[:status]
      assert_equal :draft, source.find_by(season_code: "s02", episode_number: 2, context: :admin)[:status]
    end
  end

  test "keeps archived body in protected direct storage only" do
    with_snapshot(s01_status: "archived", s02_status: "review") do |root|
      source = seasoned(root)

      assert_empty source.public_chapters
      assert_nil source.find("S01E01")
      archived = source.find_direct("S01E01")
      assert_equal :archived, archived[:status]
      assert archived[:protected]
      assert source.body_path(archived, context: :direct).to_s.include?("protected/archived/s01")
      assert_nil source.body_path(archived, context: :public)
      assert root.join("protected/archived/s01/S01E01_first.md").file?
      assert_not root.join("s01/S01E01_first.md").exist?
    end
  end

  test "resolves images inside the requested visibility root and rejects escapes" do
    with_parity_snapshot do |root|
      source = seasoned(root)

      assert source.image_path(season_code: "s01", relative_path: "used.png").file?
      assert source.image_path(season_code: "s01", relative_path: "nested/diagram.png").file?
      assert_nil source.image_path(season_code: "s01", relative_path: "../catalog.yml")
      assert_nil source.image_path(season_code: "s01", relative_path: "nested\\diagram.png")
    end
  end

  test "invalid snapshots expose diagnostics and never fall back to legacy chapters" do
    with_parity_snapshot do |root|
      root.join("s01/S01E01_overview.md").write("tampered")
      source = seasoned(root)

      assert_not source.usable?
      assert_empty source.chapters
      assert_includes source.diagnostics.pluck(:code), :snapshot_checksum_mismatch
    end
  end

  test "source selection defaults to legacy and requires explicit seasoned mode" do
    with_env("CHATDOX_CONTENT_SOURCE" => nil, "CHATDOX_SNAPSHOT_PATH" => nil) do
      assert_instance_of ProductContent::ChatdoxLegacySource, ProductContent.for("chatdox")
    end

    with_parity_snapshot do |root|
      with_env("CHATDOX_CONTENT_SOURCE" => "seasoned", "CHATDOX_SNAPSHOT_PATH" => root.to_s) do
        selected = ProductContent.for("chatdox")
        assert_instance_of ProductContent::ChatdoxSeasonedCompatibilityAdapter, selected
        assert_equal 20, selected.chapters.length
      end
    end

    with_env("CHATDOX_CONTENT_SOURCE" => "unknown") do
      selected = ProductContent.for("chatdox")
      assert_instance_of ProductContent::InvalidChatdoxSource, selected
      assert_empty selected.chapters
      assert_equal :invalid_chatdox_source_mode, selected.diagnostics.first.code
    end
  end

  private

  COMMIT = "a" * 40

  def seasoned(root)
    ProductContent::ChatdoxSeasonedSource.new("chatdox", snapshot_path: root)
  end

  def with_parity_snapshot
    Dir.mktmpdir do |directory|
      base = Pathname.new(directory)
      source = base.join("source")
      create_product_tree(source, s02_status: "review")
      write_s01_parity(source)
      target = base.join("runtime")
      ContentSnapshot::Builder.new(source_root: source, source_commit: COMMIT, target:).build!
      yield target
    end
  end

  def with_snapshot(s01_status:, s02_status:)
    Dir.mktmpdir do |directory|
      base = Pathname.new(directory)
      source = base.join("source")
      create_product_tree(source, s01_status:, s02_status:)
      target = base.join("runtime")
      ContentSnapshot::Builder.new(source_root: source, source_commit: COMMIT, target:).build!
      yield target
    end
  end

  def write_s01_parity(root)
    season = root.join("s01")
    chapters = ProductContent::ChatdoxLegacySource::CHAPTERS.map.with_index(1) do |legacy, number|
      slug = "S01E#{format('%02d', number)}_#{legacy[:slug].split('_', 2).last}"
      season.join("#{slug}.md").write("# #{legacy[:title]}\n") unless number == 1
      {
        "id" => format("S01E%02d", number), "number" => number, "order" => number,
        "slug" => slug, "title" => legacy[:title], "status" => "published", "phase" => phase_for(number)
      }
    end
    season.join("S01E01_overview.md").write(season.join("S01E01_first.md").read)
    phases = ProductContent::ChatdoxLegacySource::PHASES.map do |phase|
      {
        "key" => phase[:key], "order" => phase[:key].delete_prefix("phase_").to_i, "title" => phase[:title],
        "episode_ids" => phase[:range].map { |number| format("S01E%02d", number) }
      }
    end
    season.join("content_meta.yml").write({
      "schema_version" => 1,
      "season" => {
        "code" => "s01", "order" => 1, "title" => "CHATDOX Season 01", "status" => "completed",
        "guest_episode_limit" => 2, "trial_episode_limit" => 5, "images_dir" => "images"
      },
      "phases" => phases,
      "episodes" => chapters
    }.to_yaml)
  end

  def phase_for(number)
    return "phase_1" if number <= 5
    return "phase_2" if number <= 16

    "phase_3"
  end

  def with_env(values)
    previous = values.to_h { |key, _value| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
