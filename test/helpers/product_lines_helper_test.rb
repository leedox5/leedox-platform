require "test_helper"

# Handoff 0071 R1 -- the hero's release label (counts only; no episode numbers are shown to visitors).
class ProductLinesHelperTest < ActionView::TestCase
  def eps(count) = Array.new(count) { Object.new }

  test "the release line counts both halves, or just the published count when nothing is coming" do
    assert_equal "공개 2편 · 공개 예정 3편", series_release_label(eps(2), eps(3))
    assert_equal "공개 2편", series_release_label(eps(2), [])
    assert_equal "공개 예정 3편", series_release_label([], eps(3))
  end
end
