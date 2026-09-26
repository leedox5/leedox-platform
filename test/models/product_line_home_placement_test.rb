require "test_helper"

# Handoff 0071 R1 (a) -- ProductLine#track and #featured: the home row a series appears in, and the single
# featured (hero) series.
class ProductLineHomePlacementTest < ActiveSupport::TestCase
  def line(slug, **attrs)
    ProductLine.create!({ internal_name: slug, customer_name: slug, slug: slug, introduction: "소개", status: "published" }.merge(attrs))
  end

  test "track is basics, ai or nothing; a blank select value is stored as nothing" do
    assert line("t-basics", track: "basics").valid?
    assert line("t-ai", track: "ai").valid?
    assert_nil line("t-blank", track: "").track
    assert_not ProductLine.new(internal_name: "x", customer_name: "x", slug: "t-bad", introduction: "소개", track: "games").valid?
  end

  test "turning a series featured quietly un-features the previous one, in the same save" do
    first = line("feat-a", featured: true)
    second = line("feat-b")

    second.update!(featured: true)
    assert second.reload.featured?
    assert_not first.reload.featured?, "the old hero is switched off, not an error"
    assert_equal 1, ProductLine.where(featured: true).count
  end

  test "turning the featured series off leaves no featured series at all" do
    only = line("feat-only", featured: true)
    only.update!(featured: false)
    assert_equal 0, ProductLine.where(featured: true).count
  end

  test "saving an unrelated field of the featured series doesn't disturb anything" do
    hero = line("feat-hero", featured: true)
    hero.update!(summary: "바뀐 요약")
    assert hero.reload.featured?
  end

  test "the database itself refuses a second featured row even if the model callback is bypassed" do
    line("feat-db-a", featured: true)
    other = line("feat-db-b")
    assert_raises(ActiveRecord::RecordNotUnique) { other.update_columns(featured: true) }
  end

  test "published_episodes and upcoming_episodes split exactly like the product page (0070)" do
    series = line("eps-line")
    series.content_episodes.create!(position: 2, customer_title: "둘째", status: "published")
    series.content_episodes.create!(position: 1, customer_title: "첫째", status: "published")
    series.content_episodes.create!(position: 4, customer_title: "넷째", status: "draft")
    series.content_episodes.create!(position: 3, customer_title: " ", status: "draft") # untitled -- never named
    series.content_episodes.create!(position: 5, customer_title: "보류", status: "in_review")

    assert_equal [ 1, 2 ], series.published_episodes.map(&:position)
    assert_equal [ 4 ], series.upcoming_episodes.map(&:position)
  end
end
