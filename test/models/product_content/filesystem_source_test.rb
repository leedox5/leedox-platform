require "test_helper"

class ProductContent::FilesystemSourceTest < ActiveSupport::TestCase
  # Parity checks against the old Claudox model (still present during the
  # migration) -- Claudox is the first real-world user of FilesystemSource,
  # via hq/claudox/content_meta.yml.
  setup do
    @source = ProductContent.for("claudox")
  end

  test "chapters match Claudox.all exactly (id/slug/title/kind/product_code/available)" do
    old_chapters = Claudox.all
    new_chapters = @source.chapters

    assert_equal old_chapters.size, new_chapters.size
    old_chapters.zip(new_chapters).each do |old_chapter, new_chapter|
      assert_equal old_chapter, new_chapter
    end
  end

  test "find matches Claudox.find for a regular chapter and an appendix chapter" do
    assert_equal Claudox.find("05"), @source.find("05")
    assert_equal Claudox.find("90"), @source.find("90")
  end

  test "97_commands.md is excluded, matching Claudox's NON_CHAPTER_FILES behavior" do
    assert_nil Claudox.find("97")
    assert_nil @source.find("97")
  end

  test "phases match Claudox.phases exactly" do
    assert_equal Claudox.phases, @source.phases
  end

  test "licensed_chapter_ranges/guest/trial limits match the current DocPolicy hardcoded values" do
    assert_equal [ 1..20, 90..99 ], @source.licensed_chapter_ranges
    assert_equal 2, @source.guest_chapter_limit
    assert_equal 5, @source.trial_chapter_limit
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
