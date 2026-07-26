require "test_helper"

class ProductContent::ChatdoxLegacySourceTest < ActiveSupport::TestCase
  setup do
    @source = ProductContent::ChatdoxLegacySource.new("chatdox")
  end

  test "chapters returns all 20 hardcoded chapters, in order, with product_code/kind/available" do
    chapters = @source.chapters
    assert_equal 20, chapters.size
    assert_equal (1..20).map { |n| n.to_s.rjust(2, "0") }, chapters.map { |c| c[:id] }

    first = chapters.first
    assert_equal "01_overview", first[:slug]
    assert_equal "채독스 전체 구조 이해", first[:title]
    assert_equal "chatdox", first[:product_code]
    assert_equal :chapter, first[:kind]
    assert_equal File.exist?(Rails.root.join("hq/chatdox/01_overview.md")), first[:available]
  end

  test "find looks up a chapter by id and normalizes single-digit ids" do
    assert_equal "채독스 전체 구조 이해", @source.find("01")[:title]
    assert_equal @source.find("1")[:title], @source.find("01")[:title]
  end

  test "find returns nil for an id outside 1..20 (the fixed chapter list)" do
    assert_nil @source.find("21")
  end

  test "phases are the 3 hardcoded Phase 1/2/3 groups" do
    labels = @source.phases.map { |phase| phase[:label] }
    assert_equal [ "Phase 1", "Phase 2", "Phase 3" ], labels
    assert_equal 1..5, @source.phases[0][:range]
    assert_equal 6..16, @source.phases[1][:range]
    assert_equal 17..20, @source.phases[2][:range]
  end

  test "licensed_chapter_ranges/guest/trial limits match the current DocPolicy hardcoded values" do
    assert_equal [ 1..20 ], @source.licensed_chapter_ranges
    assert_equal 2, @source.guest_chapter_limit
    assert_equal 5, @source.trial_chapter_limit
  end

  test "missing_chapter_message matches the original DocsController out-of-range message" do
    assert_equal "챕터를 찾을 수 없습니다.", @source.missing_chapter_message
  end

  test "editorial_status is missing/written for an out-of-range vs a real, existing chapter" do
    assert_equal :missing, @source.editorial_status("99")
    assert_equal :written, @source.editorial_status("01")
  end

  test "last_updated_at delegates to ContentManifest against the product's own path, zone-converted" do
    result = @source.last_updated_at("01_overview")
    assert_equal ContentManifest.last_updated_at(@source.path, "01_overview"), result
    assert_equal ActiveSupport::TimeZone["Asia/Seoul"], result.time_zone
  end
end
