require "test_helper"

class ProductContent::ContentMetaTest < ActiveSupport::TestCase
  test "loads phases/ranges/limits from content_meta.yml" do
    Dir.mktmpdir do |dir|
      directory = Pathname.new(dir)
      File.write(directory.join("content_meta.yml"), <<~YAML)
        phases:
          - key: part_1
            label: "Part 1"
            title: "입문"
            description: "설명"
            range: "1..8"
        chapter_range: "1..20"
        appendix_range: "90..99"
        non_chapter_files: [97_commands.md]
        guest_chapter_limit: 3
        trial_chapter_limit: 7
      YAML

      meta = ProductContent::ContentMeta.load(directory)

      assert_equal 1, meta.phases.size
      assert_equal 1..8, meta.phases.first[:range]
      assert_equal "Part 1", meta.phases.first[:label]
      assert_equal 1..20, meta.chapter_range
      assert_equal 90..99, meta.appendix_range
      assert_equal [ "97_commands.md" ], meta.non_chapter_files
      assert_equal 3, meta.guest_chapter_limit
      assert_equal 7, meta.trial_chapter_limit
      assert_equal [ 1..20, 90..99 ], meta.licensed_chapter_ranges
    end
  end

  test "falls back to sane defaults when there is no content_meta.yml at all" do
    Dir.mktmpdir do |dir|
      meta = ProductContent::ContentMeta.load(Pathname.new(dir))

      assert_equal [], meta.phases
      assert_equal 1..20, meta.chapter_range
      assert_nil meta.appendix_range
      assert_equal [], meta.non_chapter_files
      assert_equal 2, meta.guest_chapter_limit
      assert_equal 5, meta.trial_chapter_limit
      assert_equal [ 1..20 ], meta.licensed_chapter_ranges
    end
  end

  test "a product with no appendix_range simply has no appendix entry in licensed_chapter_ranges" do
    Dir.mktmpdir do |dir|
      directory = Pathname.new(dir)
      File.write(directory.join("content_meta.yml"), "chapter_range: \"1..10\"\n")

      meta = ProductContent::ContentMeta.load(directory)

      assert_equal [ 1..10 ], meta.licensed_chapter_ranges
    end
  end
end
