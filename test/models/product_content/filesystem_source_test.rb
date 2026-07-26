require "test_helper"

class ProductContent::FilesystemSourceTest < ActiveSupport::TestCase
  # Claudox is the first real-world user of FilesystemSource, via
  # hq/claudox/content_meta.yml -- these values were verified against the old
  # Claudox model's output during the migration (see stage 3 result.md); that
  # model is gone now, so they're pinned here as plain expected values.
  setup do
    @source = ProductContent.for("claudox")
  end

  test "chapters are scanned from disk, sorted by id, and carry the expected shape" do
    chapters = @source.chapters

    assert_equal chapters.map { |c| c[:id] }, chapters.map { |c| c[:id] }.sort
    first = chapters.find { |c| c[:id] == "01" }
    assert first[:title].present?
    assert_equal "01_first_meeting", first[:slug]
    assert_equal "claudox", first[:product_code]
    assert_equal :chapter, first[:kind]
    assert first[:available]
  end

  test "find looks up a single chapter by id, normalizing to a zero-padded two-digit id" do
    assert_equal @source.find("1")[:id], @source.find("01")[:id]
  end

  test "find distinguishes regular chapters (kind: :chapter) from the appendix range (kind: :appendix)" do
    assert_equal :chapter, @source.find("05")[:kind]
    assert_equal :appendix, @source.find("90")[:kind]
  end

  test "find returns nil for a chapter number with no matching file" do
    assert_nil @source.find("98")
  end

  test "97_commands.md is excluded despite matching the 90..99 appendix range (non_chapter_files)" do
    assert_nil @source.find("97")
    assert_not_includes @source.chapters.map { |c| c[:id] }, "97"
  end

  test "phases come from content_meta.yml (Part 1/2/3, matching the old Claudox::PHASES data)" do
    labels = @source.phases.map { |phase| phase[:label] }
    assert_equal [ "Part 1", "Part 2", "Part 3" ], labels
    assert_equal 1..8, @source.phases[0][:range]
    assert_equal 9..15, @source.phases[1][:range]
    assert_equal 16..20, @source.phases[2][:range]
  end

  test "licensed_chapter_ranges/guest/trial limits come from content_meta.yml" do
    assert_equal [ 1..20, 90..99 ], @source.licensed_chapter_ranges
    assert_equal 2, @source.guest_chapter_limit
    assert_equal 5, @source.trial_chapter_limit
  end

  test "last_updated_at delegates to ContentManifest against the product's own path, zone-converted" do
    result = @source.last_updated_at("01_first_meeting")
    assert_equal ContentManifest.last_updated_at(@source.path, "01_first_meeting"), result
    assert_equal ActiveSupport::TimeZone["Asia/Seoul"], result.time_zone
  end

  test "an unregistered product with no content_meta.yml at all still works with sane defaults" do
    source = ProductContent.for("some_future_product_nobody_registered")

    assert_equal [], source.chapters
    assert_equal [], source.phases
    assert_equal [ 1..20 ], source.licensed_chapter_ranges
    assert_equal 2, source.guest_chapter_limit
    assert_equal 5, source.trial_chapter_limit
  end
end
