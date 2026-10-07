require "test_helper"

# Handoff 0096 -- a guide card's episode count on the home: published episodes only, 공개 예정 when there are none.
# (Replaces 0071's release-line test -- that line and its helper went with the old hero.) 0097: "에피소드 N" (was "N편").
class ProductLinesHelperTest < ActionView::TestCase
  test "에피소드 N counts published episodes; none yet reads 공개 예정" do
    assert_equal "에피소드 5", guide_episode_count_label(5)
    assert_equal "에피소드 1", guide_episode_count_label(1)
    assert_equal "공개 예정", guide_episode_count_label(0)
  end
end
