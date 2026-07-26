require "test_helper"

class ProductContent::ChatdoxLegacySourceTest < ActiveSupport::TestCase
  setup do
    @source = ProductContent::ChatdoxLegacySource.new("chatdox")
  end

  test "chapters match Curriculum::CHAPTERS exactly (id/slug/title), plus product_code/kind/available" do
    assert_equal Curriculum::CHAPTERS.size, @source.chapters.size

    Curriculum::CHAPTERS.zip(@source.chapters).each do |old_chapter, new_chapter|
      assert_equal old_chapter[:id], new_chapter[:id]
      assert_equal old_chapter[:slug], new_chapter[:slug]
      assert_equal old_chapter[:title], new_chapter[:title]
      assert_equal "chatdox", new_chapter[:product_code]
      assert_equal :chapter, new_chapter[:kind]
      assert_equal File.exist?(Rails.root.join("hq/chatdox/#{old_chapter[:slug]}.md")), new_chapter[:available]
    end
  end

  test "find matches Curriculum.find for every chapter id" do
    Curriculum::CHAPTERS.each do |chapter|
      assert_equal chapter[:title], @source.find(chapter[:id])[:title]
    end
  end

  test "find normalizes single-digit ids the same way Curriculum.find does" do
    assert_equal Curriculum.find("1")[:title], @source.find("1")[:title]
  end

  test "find returns nil for an id outside 1..20, matching Curriculum.find" do
    assert_nil Curriculum.find("21")
    assert_nil @source.find("21")
  end

  test "phases match Curriculum.phases exactly" do
    assert_equal Curriculum.phases, @source.phases
  end

  test "licensed_chapter_ranges/guest/trial limits match the current DocPolicy hardcoded values" do
    assert_equal [ 1..20 ], @source.licensed_chapter_ranges
    assert_equal 2, @source.guest_chapter_limit
    assert_equal 5, @source.trial_chapter_limit
  end

  test "missing_chapter_message matches DocsController's out-of-range message" do
    assert_equal "챕터를 찾을 수 없습니다.", @source.missing_chapter_message
  end

  test "editorial_status is missing/written for an out-of-range vs a real, existing chapter" do
    assert_equal :missing, @source.editorial_status("99")
    assert_equal :written, @source.editorial_status("01")
  end
end
