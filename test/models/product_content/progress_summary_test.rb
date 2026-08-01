require "test_helper"

class ProductContent::ProgressSummaryTest < ActiveSupport::TestCase
  SyntheticSource = Struct.new(:product_code, :public_chapters, :usable, :seasons, keyword_init: true) do
    def usable? = usable
    def find(id) = public_chapters.find { |chapter| chapter[:id] == id }
  end

  setup do
    Commerce::CatalogBootstrap.call!
    @user = User.create!(name: "Summary User", email: "progress-summary@example.com", password: "password123")
  end

  test "dedupes numeric and canonical S01 rows and returns overall and season next" do
    create_progress("01")
    create_progress("S01E01", at: 1.hour.ago)
    create_progress("02")

    summary = ProductContent::ProgressSummary.call(user: @user, source: source(s01_count: 20))

    assert_equal 2, summary.overall.completed_count
    assert_equal 20, summary.overall.available_count
    assert_equal 10, summary.overall.percentage
    assert_equal "S01E03", summary.overall.next_chapter[:id]
    assert_equal "S01E03", summary.season("s01").next_chapter[:id]
  end

  test "zero episode season is unavailable and never 100 percent" do
    summary = ProductContent::ProgressSummary.call(user: @user, source: source(s01_count: 2, include_empty_s02: true))

    assert_equal 0, summary.season("s02").available_count
    assert_equal 0, summary.season("s02").percentage
    assert_not summary.season("s02").available?
    assert_equal 0, summary.overall.percentage
  end

  test "a newly public S02 episode lowers overall percentage and becomes next" do
    20.times { |index| create_progress(format("S01E%02d", index + 1)) }
    before = ProductContent::ProgressSummary.call(user: @user, source: source(s01_count: 20))
    after = ProductContent::ProgressSummary.call(user: @user, source: source(s01_count: 20, s02_count: 1))

    assert_equal 100, before.overall.percentage
    assert_equal 95, after.overall.percentage
    assert_equal [ 20, 21 ], [ after.overall.completed_count, after.overall.available_count ]
    assert_equal "S02E01", after.overall.next_chapter[:id]
  end

  test "guest and unusable sources return stable empty values" do
    guest = ProductContent::ProgressSummary.call(user: nil, source: source(s01_count: 2))
    invalid = ProductContent::ProgressSummary.call(user: @user, source: source(s01_count: 2, usable: false))

    assert_equal 0, guest.overall.completed_count
    assert guest.available?
    assert_equal :unavailable, invalid.status
    assert_not invalid.overall.available?
  end

  private

  def create_progress(id, at: Time.current)
    ChapterProgress.create!(user: @user, product_code: "chatdox", chapter_id: id, completed_at: at)
  end

  def source(s01_count:, s02_count: 0, include_empty_s02: false, usable: true)
    chapters = Array.new(s01_count) { |index| chapter("s01", index + 1) }
    chapters.concat(Array.new(s02_count) { |index| chapter("s02", index + 1) })
    seasons = [ { code: "s01" } ]
    seasons << { code: "s02" } if include_empty_s02 || s02_count.positive?
    SyntheticSource.new(product_code: "chatdox", public_chapters: chapters, usable:, seasons:)
  end

  def chapter(season, number)
    id = format("%sE%02d", season.upcase, number)
    { id:, canonical_id: id, season_code: season, available: true, kind: :chapter }
  end
end
