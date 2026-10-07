require "test_helper"

# Handoff 0096 -- a guide card's episode count on the home: published episodes only, 공개 예정 when there are none.
# (Replaces 0071's release-line test -- that line and its helper went with the old hero.)
class ProductLinesHelperTest < ActionView::TestCase
  test "N편 counts published episodes; none yet reads 공개 예정" do
    assert_equal "5편", guide_episode_count_label(5)
    assert_equal "1편", guide_episode_count_label(1)
    assert_equal "공개 예정", guide_episode_count_label(0)
  end
end
