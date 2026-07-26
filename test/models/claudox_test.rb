require "test_helper"

class ClaudoxTest < ActiveSupport::TestCase
  test "all returns chapters sorted by id with titles extracted from the markdown heading" do
    chapters = Claudox.all

    assert_equal chapters.map { |c| c[:id] }, chapters.map { |c| c[:id] }.sort
    first = chapters.first
    assert_equal "01", first[:id]
    assert_equal "claudox", first[:product_code]
    assert first[:available]
    assert first[:title].present?
  end

  test "find looks up a single chapter by id, normalizing to a zero-padded two-digit id" do
    chapter = Claudox.find("1")

    assert_equal "01", chapter[:id]
    assert_equal Claudox.all.first[:title], chapter[:title]
  end

  test "find returns nil for a chapter number with no matching file" do
    assert_nil Claudox.find("98")
  end

  test "regular chapters are kind: :chapter, the 90..99 appendix range is kind: :appendix" do
    assert_equal :chapter, Claudox.find("01")[:kind]

    appendix = Claudox.all.find { |chapter| chapter[:id] == "90" }
    assert appendix, "expected the fixture appendix file 90_session_mechanics.md to be picked up"
    assert_equal :appendix, appendix[:kind]
  end

  test "97_commands.md is not exposed as an appendix chapter despite matching the 90..99 range" do
    assert_nil Claudox.find("97"), "97_commands.md is a command-shorthand reference doc, not reader content"
    assert_not_includes Claudox.all.map { |chapter| chapter[:id] }, "97"
  end

  # AC: adding a new appendix file (e.g. 91_*.md) must need no code change.
  # This is deliberately NOT tested by writing a real file into hq/claudox/ --
  # bin/rails test runs in parallel worker processes that all call
  # Claudox.all concurrently, and a transient file there was observed to
  # cause a real ENOENT race (another worker's Dir.glob sees the file, then
  # File.foreach loses the read race against this test's cleanup). Instead,
  # this proves the same thing without touching shared state: appendix
  # classification is purely a number-range check with no id allowlist, so
  # any 90..99 file that shows up on disk is picked up by construction.
  test "appendix classification is a pure number-range check, not a hardcoded id list (AC: file-only extensibility)" do
    assert_equal :appendix, Claudox.send(:chapter_kind, 91)
    assert_equal :appendix, Claudox.send(:chapter_kind, 99)
    assert_nil Claudox.send(:chapter_kind, 89)
    assert_nil Claudox.send(:chapter_kind, 100)
  end

  test "last_updated_at delegates to ContentManifest against CLAUDOX_PATH" do
    result = Claudox.last_updated_at("01_first_meeting")
    assert_equal ContentManifest.last_updated_at(Claudox::CLAUDOX_PATH, "01_first_meeting"), result
  end
end
