require "test_helper"

# Handoff 0071 R1 -- the hero's episode-number and release labels.
class ProductLinesHelperTest < ActionView::TestCase
  Ep = Struct.new(:position) do
    def display_id = position.to_s.rjust(2, "0")
  end

  def eps(*positions) = positions.map { |p| Ep.new(p) }

  test "two numbers are dot-joined, three or more in a row collapse to a range" do
    assert_equal "E01", episode_numbers_label(eps(1))
    assert_equal "E01·E02", episode_numbers_label(eps(1, 2))
    assert_equal "E03~E05", episode_numbers_label(eps(3, 4, 5))
    assert_equal "E01·E03~E05", episode_numbers_label(eps(1, 3, 4, 5))
  end

  test "the release line names both halves, or just the published count when nothing is coming" do
    assert_equal "E01·E02 공개 · E03~E05 공개 예정", series_release_label(eps(1, 2), eps(3, 4, 5))
    assert_equal "공개 2편", series_release_label(eps(1, 2), [])
    assert_equal "E01~E03 공개 예정", series_release_label([], eps(1, 2, 3))
  end
end
