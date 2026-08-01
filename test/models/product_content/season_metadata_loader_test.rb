require "test_helper"

class ProductContent::SeasonMetadataLoaderTest < ActiveSupport::TestCase
  test "compiles deterministic S02 chapters, tiers, timestamp, and paths" do
    with_season do |root|
      result = load_season(root)

      assert result.valid?
      assert_equal %w[S02E01 S02E02 S02E03 S02E04], result.chapters.pluck(:id)
      assert_equal %i[guest trial license unpublished], result.chapters.pluck(:access_tier)
      assert_equal [ "S02E01", "S02E02", "S02E03" ], result.public_chapters.pluck(:id)
      assert_equal "01", result.chapters.first[:display_number]
      assert_equal "s02/S02E01_first.md", result.chapters.first[:manifest_key]
      assert_equal "foundation", result.chapters.first[:phase_key]
      assert_equal Time.zone.parse("2026-08-01T09:00:00+09:00"), result.chapters.first[:published_at]
      assert_equal root.join("images"), result.images_path
      assert result.chapters.first.frozen?
    end
  end

  test "loads S03 without adding a code constant" do
    with_season(code: "s03", order: 3) do |root|
      result = load_season(root)

      assert result.valid?
      assert_equal "s03", result.season[:code]
      assert_equal "S03E01", result.chapters.first[:id]
      assert_equal "s03/S03E01_first.md", result.chapters.first[:manifest_key]
    end
  end

  test "future published_at remains published" do
    with_season do |root, metadata|
      metadata["episodes"][0]["published_at"] = "2099-01-01T00:00:00+09:00"
      write_metadata(root, metadata)

      chapter = load_season(root).chapters.first
      assert chapter[:available]
      assert_equal :guest, chapter[:access_tier]
    end
  end

  test "published_at is optional" do
    with_season do |root, metadata|
      metadata["episodes"].find { |episode| episode["id"] == "S02E01" }.delete("published_at")
      write_metadata(root, metadata)

      result = load_season(root)
      assert result.valid?
      assert_nil result.chapters.first[:published_at]
    end
  end

  test "invalid published_at excludes the affected episode" do
    with_season do |root, metadata|
      metadata["episodes"].find { |episode| episode["id"] == "S02E01" }["published_at"] = "tomorrow morning"
      write_metadata(root, metadata)
      result = load_season(root)

      assert_includes result.diagnostics.pluck(:code), :invalid_published_at
      assert_not_includes result.chapters.pluck(:id), "S02E01"
      assert_not_empty result.public_chapters
    end
  end

  test "syntax errors and unsafe YAML fail closed" do
    with_raw_metadata("s02", "schema_version: [") do |root|
      assert_failure(load_season(root), :yaml_syntax_error)
    end

    with_raw_metadata("s02", "--- !ruby/object:Object {}\n") do |root|
      assert_failure(load_season(root), :unsafe_yaml_object)
    end

    with_raw_metadata("s02", "base: &base { code: s02 }\nseason: *base\n") do |root|
      assert_failure(load_season(root), :yaml_alias_forbidden)
    end
  end

  test "missing metadata fails closed" do
    Dir.mktmpdir do |directory|
      result = load_season(Pathname.new(directory).join("s02"))

      assert_failure(result, :metadata_missing)
    end
  end

  test "missing and unsupported schema versions fail the whole season" do
    with_season do |root, metadata|
      metadata.delete("schema_version")
      write_metadata(root, metadata)
      assert_global_failure(load_season(root), :missing_schema_version)

      metadata["schema_version"] = 2
      write_metadata(root, metadata)
      assert_global_failure(load_season(root), :unsupported_schema_version)
    end
  end

  test "season identity status limits and directory are strict" do
    cases = {
      invalid_season: ->(metadata) { metadata["season"]["code"] = "season2" },
      season_directory_mismatch: ->(metadata) { metadata["season"]["code"] = "s03" },
      unknown_season_status: ->(metadata) { metadata["season"]["status"] = "live" },
      invalid_guest_limit: ->(metadata) { metadata["season"]["guest_episode_limit"] = -1 },
      guest_limit_exceeds_trial_limit: ->(metadata) { metadata["season"]["guest_episode_limit"] = 3 }
    }

    cases.each do |code, mutation|
      with_season do |root, metadata|
        mutation.call(metadata)
        write_metadata(root, metadata)
        assert_global_failure(load_season(root), code)
      end
    end
  end

  test "limits larger than the published count do not crash" do
    with_season do |root, metadata|
      metadata["season"]["guest_episode_limit"] = 10
      metadata["season"]["trial_episode_limit"] = 20
      write_metadata(root, metadata)

      result = load_season(root)
      assert result.valid?
      assert_equal %i[guest guest guest], result.public_chapters.pluck(:access_tier)
    end
  end

  test "invalid episode fields fail closed" do
    mutations = {
      invalid_episode_id: ->(episode) { episode["id"] = "02" },
      episode_season_mismatch: ->(episode) { episode["id"] = "S03E01" },
      episode_number_mismatch: ->(episode) { episode["number"] = 9 },
      invalid_episode_order: ->(episode) { episode["order"] = 0 },
      unsafe_episode_slug: ->(episode) { episode["slug"] = "../secret" },
      unknown_episode_status: ->(episode) { episode["status"] = "scheduled" },
      unknown_episode_phase: ->(episode) { episode["phase"] = "missing" }
    }

    mutations.each do |code, mutation|
      with_season do |root, metadata|
        mutation.call(metadata["episodes"][0])
        write_metadata(root, metadata)
        result = load_season(root)

        assert_includes result.diagnostics.pluck(:code), code
        assert_not_includes result.chapters.pluck(:id), metadata["episodes"][0]["id"]
      end
    end
  end

  test "duplicate episode identities and ordering fail the whole season" do
    {
      duplicate_episode_id: "id",
      duplicate_episode_number: "number",
      duplicate_episode_order: "order",
      duplicate_episode_slug: "slug"
    }.each do |code, field|
      with_season do |root, metadata|
        metadata["episodes"][1][field] = metadata["episodes"][0][field]
        write_metadata(root, metadata)
        assert_global_failure(load_season(root), code)
      end
    end
  end

  test "phase structure, references, membership, and orphan episodes are diagnosed" do
    with_season do |root, metadata|
      metadata["phases"] << {
        "key" => "foundation",
        "order" => 2,
        "title" => "Duplicate",
        "episode_ids" => []
      }
      write_metadata(root, metadata)
      assert_global_failure(load_season(root), :duplicate_phase_key)
    end

    with_season do |root, metadata|
      metadata["phases"][0]["order"] = 0
      write_metadata(root, metadata)
      assert_global_failure(load_season(root), :invalid_phase_order)
    end

    with_season do |root, metadata|
      metadata["phases"][0]["episode_ids"] << "S02E99"
      metadata["phases"][0]["episode_ids"].delete("S02E01")
      write_metadata(root, metadata)
      result = load_season(root)

      assert_includes result.diagnostics.pluck(:code), :unknown_phase_episode
      assert_includes result.diagnostics.pluck(:code), :orphan_episode
      assert_empty result.chapters
    end

    with_season do |root, metadata|
      metadata["phases"] << {
        "key" => "advanced", "order" => 2, "title" => "Advanced", "episode_ids" => [ "S02E01" ]
      }
      write_metadata(root, metadata)
      assert_includes load_season(root).diagnostics.pluck(:code), :duplicate_episode_membership
    end
  end

  test "missing published body excludes only that episode without promoting later tiers" do
    with_season do |root|
      root.join("S02E01_first.md").delete
      result = load_season(root)

      assert_includes result.diagnostics.pluck(:code), :published_body_missing
      assert_equal %w[S02E02 S02E03 S02E04], result.chapters.pluck(:id)
      assert_equal :trial, result.chapters.first[:access_tier]
      assert_equal :license, result.chapters.second[:access_tier]
    end
  end

  test "stray Markdown is never discovered" do
    with_season do |root|
      root.join("S02E99_stray.md").write("# Stray")

      assert_not_includes load_season(root).chapters.pluck(:id), "S02E99"
    end
  end

  test "unsafe path separators and symlink escapes fail closed" do
    with_season do |root, metadata|
      metadata["season"]["images_dir"] = "..\\images"
      write_metadata(root, metadata)
      assert_global_failure(load_season(root), :unsafe_images_dir)
    end

    Dir.mktmpdir do |outside|
      with_season do |root|
        root.join("images").rmtree
        File.symlink(outside, root.join("images"))
        assert_global_failure(load_season(root), :unsafe_images_dir)
      end
    end

    Dir.mktmpdir do |outside|
      Pathname.new(outside).join("body.md").write("# Outside")
      with_season do |root|
        root.join("S02E01_first.md").delete
        File.symlink(Pathname.new(outside).join("body.md"), root.join("S02E01_first.md"))
        result = load_season(root)
        assert_includes result.diagnostics.pluck(:code), :body_path_escape
        assert_not_includes result.chapters.pluck(:id), "S02E01"
      end
    end
  end

  test "diagnostics are deterministic and do not expose YAML contents" do
    with_season do |root, metadata|
      metadata["episodes"][0]["status"] = "SECRET_VALUE"
      metadata["episodes"][1]["slug"] = "../private"
      write_metadata(root, metadata)

      first = load_season(root).diagnostics.map(&:to_h)
      second = load_season(root).diagnostics.map(&:to_h)
      assert_equal first, second
      assert_equal %i[unknown_episode_status unsafe_episode_slug], first.pluck(:code)
      assert first.all? { |diagnostic| diagnostic.keys == %i[severity code location message] }
      assert first.none? { |diagnostic| diagnostic[:message].include?("schema_version") }
    end
  end

  private

  def load_season(root)
    ProductContent::SeasonMetadataLoader.load(root:)
  end

  def with_season(code: "s02", order: 2)
    Dir.mktmpdir do |directory|
      root = Pathname.new(directory).join(code)
      root.mkpath
      root.join("images").mkpath
      metadata = valid_metadata(code:, order:)
      write_metadata(root, metadata)
      metadata["episodes"].select { |episode| episode["status"] == "published" }.each do |episode|
        root.join("#{episode["slug"]}.md").write("# #{episode["title"]}\n")
      end
      yield root, metadata
    end
  end

  def with_raw_metadata(code, contents)
    Dir.mktmpdir do |directory|
      root = Pathname.new(directory).join(code)
      root.mkpath
      root.join("content_meta.yml").write(contents)
      yield root
    end
  end

  def write_metadata(root, metadata)
    root.join("content_meta.yml").write(metadata.to_yaml)
  end

  def valid_metadata(code:, order:)
    prefix = code.upcase
    {
      "schema_version" => 1,
      "season" => {
        "code" => code,
        "order" => order,
        "title" => "CHATDOX Season #{order}",
        "status" => "publishing",
        "guest_episode_limit" => 1,
        "trial_episode_limit" => 2,
        "images_dir" => "images"
      },
      "phases" => [ {
        "key" => "foundation",
        "order" => 1,
        "title" => "Foundation",
        "episode_ids" => (1..4).map { |number| format("S%02dE%02d", order, number) }
      } ],
      "episodes" => [
        episode(prefix, 3, "published"),
        episode(prefix, 1, "published", published_at: "2026-08-01T09:00:00+09:00"),
        episode(prefix, 2, "published"),
        episode(prefix, 4, "review")
      ]
    }
  end

  def episode(prefix, number, status, published_at: nil)
    value = {
      "id" => format("%sE%02d", prefix, number),
      "number" => number,
      "order" => number,
      "slug" => format("%sE%02d_%s", prefix, number, %w[first second third fourth][number - 1]),
      "title" => "Episode #{number}",
      "status" => status,
      "phase" => "foundation"
    }
    value["published_at"] = published_at if published_at
    value
  end

  def assert_failure(result, code)
    assert_empty result.chapters
    assert_includes result.diagnostics.pluck(:code), code
  end

  def assert_global_failure(result, code)
    assert_failure(result, code)
    assert_empty result.public_chapters
  end
end
