require "test_helper"

class ChapterProgressBackfillTest < ActiveSupport::TestCase
  setup do
    Commerce::CatalogBootstrap.call!
    @user = User.create!(name: "Backfill User", email: "progress-backfill@example.com", password: "password123")
  end

  test "dry-run reports conversion collision and unknown without mutation" do
    create_progress("01")
    create_progress("02")
    create_progress("S01E02")
    create_unknown("bad")

    result = ChapterProgressBackfill.call(dry_run: true, batch_size: 2)

    assert_equal 4, result.scanned
    assert_equal 2, result.convertible
    assert_equal 1, result.collisions
    assert_equal 1, result.canonical
    assert_equal 1, result.unknown
    assert_equal %w[01 02 S01E02 bad], ids
  end

  test "backfill converts numeric rows merges collisions with earliest completion and is idempotent" do
    early = 3.days.ago.change(usec: 0)
    late = 1.day.ago.change(usec: 0)
    legacy = create_progress("01", at: early)
    canonical = create_progress("S01E01", at: late)
    create_progress("02", at: late)
    earliest_created = [ legacy.created_at, canonical.created_at ].min

    first = ChapterProgressBackfill.call(dry_run: false, batch_size: 1)
    second = ChapterProgressBackfill.call(dry_run: false, batch_size: 1)

    assert_equal 2, first.converted
    assert_equal 1, first.collisions
    assert_equal 0, second.converted
    assert_equal %w[S01E01 S01E02], ids
    merged = ChapterProgress.find_by!(user: @user, product_code: "chatdox", chapter_id: "S01E01")
    assert_equal early, merged.completed_at
    assert_equal earliest_created, merged.created_at
  end

  test "unknown Chatdox and other product rows remain untouched" do
    create_unknown("legacy-odd")
    ChapterProgress.create!(user: @user, product_code: "claudox", chapter_id: "01", completed_at: Time.current)

    ChapterProgressBackfill.call(dry_run: false)

    assert ChapterProgress.exists?(user: @user, product_code: "chatdox", chapter_id: "legacy-odd")
    assert ChapterProgress.exists?(user: @user, product_code: "claudox", chapter_id: "01")
  end

  private

  def create_progress(id, at: Time.current)
    ChapterProgress.create!(user: @user, product_code: "chatdox", chapter_id: id, completed_at: at)
  end

  def create_unknown(id)
    ChapterProgress.insert!({
      user_id: @user.id, product_code: "chatdox", chapter_id: id,
      completed_at: Time.current, created_at: Time.current, updated_at: Time.current
    })
  end

  def ids
    @user.chapter_progresses.where(product_code: "chatdox").order(:chapter_id).pluck(:chapter_id)
  end
end
