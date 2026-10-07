require "test_helper"

# Handoff 0071 R1 (a) -- ProductLine#track and #featured: the home row a series appears in, and the featured (hero)
# series -- up to three in order since 0097.
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

  # Handoff 0097 -- up to three featured guides, in order (was one, 0071).
  test "turning guides featured puts each one last; a fourth is refused, naming the current ones, and nothing is switched off" do
    a = line("feat-a", customer_name: "가이드 A", featured: true)
    b = line("feat-b", customer_name: "가이드 B")
    b.update!(featured: true)
    c = line("feat-c", customer_name: "가이드 C", featured: true)
    assert_equal [ 1, 2, 3 ], [ a, b, c ].map { |x| x.reload.featured_position }

    fourth = line("feat-d")
    assert_not fourth.update(featured: true)
    assert_equal [ "대표 가이드는 3개까지입니다. 지금: 가이드 A, 가이드 B, 가이드 C" ], fourth.errors.full_messages
    assert_not fourth.reload.featured?
    assert_equal 3, ProductLine.where(featured: true).count
  end

  test "turning one off clears its place; the next one turned on goes last, or into the free place when 3 is taken" do
    a = line("off-a", featured: true)
    b = line("off-b", featured: true)
    c = line("off-c", featured: true)
    b.update!(featured: false)
    assert_nil b.reload.featured_position
    d = line("off-d", featured: true)
    assert_equal 2, d.reload.featured_position, "1 and 3 are taken -- the free place"
    c.update!(featured: false)
    e = line("off-e", featured: true)
    assert_equal 3, e.reload.featured_position
    assert_equal 1, a.reload.featured_position
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
    assert_equal 1, hero.featured_position
  end

  test "a place that is taken is refused with its holder's name; places are 1..3" do
    line("place-a", customer_name: "자리 주인", featured: true)
    other = line("place-b")
    assert_not other.update(featured: true, featured_position: 1)
    assert_equal [ "대표 순서 1번은 이미 '자리 주인'이(가) 쓰고 있습니다" ], other.errors.full_messages
    assert_not other.update(featured: true, featured_position: 4)
  end

  test "the database itself refuses two guides at the same place even if the model is bypassed" do
    line("feat-db-a", featured: true)
    other = line("feat-db-b")
    assert_raises(ActiveRecord::RecordNotUnique) { other.update_columns(featured: true, featured_position: 1) }
  end

  test "arrange_featured!: swaps places in one save, takes one off with a blank, refuses repeats and out-of-range places" do
    a = line("arr-a", featured: true)
    b = line("arr-b", featured: true)
    c = line("arr-c", featured: true)
    assert_nil ProductLine.arrange_featured!({ a.id.to_s => "2", b.id.to_s => "1", c.id.to_s => "" })
    assert_equal [ 2, 1, nil ], [ a, b, c ].map { |x| x.reload.featured_position }
    assert_not c.featured?

    assert_equal "대표 순서가 겹칩니다. 1~3을 하나씩 골라 주세요.", ProductLine.arrange_featured!({ a.id.to_s => "1", b.id.to_s => "1" })
    assert_equal "대표 순서는 1~3 중에서 골라 주세요.", ProductLine.arrange_featured!({ a.id.to_s => "5" })
    assert_equal [ 2, 1 ], [ a, b ].map { |x| x.reload.featured_position }, "a refused arrangement changes nothing"
  end

  test "home_featured: listed featured guides only, in their order" do
    a = line("hf-a", featured: true)
    hidden = line("hf-hidden", featured: true, status: "draft")
    c = line("hf-c", featured: true)
    ProductLine.arrange_featured!({ a.id.to_s => "3", hidden.id.to_s => "1", c.id.to_s => "2" })
    assert_equal [ c, a ], ProductLine.home_featured
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
