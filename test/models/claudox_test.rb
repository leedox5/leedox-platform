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

  test "a new appendix file is picked up automatically, no code change needed (AC: file-only extensibility)" do
    new_file = Claudox::CLAUDOX_PATH.join("91_temp_test_appendix.md")
    File.write(new_file, "# 부록. 임시 테스트 챕터\n\n본문.\n")

    chapter = Claudox.find("91")
    assert chapter, "expected a freshly-added 91_*.md file to appear without any code change"
    assert_equal :appendix, chapter[:kind]
    assert_equal "부록. 임시 테스트 챕터", chapter[:title]
  ensure
    File.delete(new_file) if new_file && File.exist?(new_file)
  end
end
