require "test_helper"

class ChapterProgressTest < ActiveSupport::TestCase
  setup do
    Commerce::CatalogBootstrap.call!
    @user = User.create!(name: "테스트 유저", email: "chapter-progress-model@example.com", password: "password123")
  end

  test "same chapter_id is allowed for different product_code (uniqueness scoped to user+chapter+product)" do
    ChapterProgress.create!(user: @user, chapter_id: "05", product_code: "chatdox", completed_at: Time.current)

    claudox_progress = ChapterProgress.new(user: @user, chapter_id: "05", product_code: "claudox", completed_at: Time.current)
    assert claudox_progress.valid?
    claudox_progress.save!

    assert_equal 2, @user.chapter_progresses.count
  end

  test "duplicate chapter_id for the same product_code is rejected" do
    ChapterProgress.create!(user: @user, chapter_id: "05", product_code: "chatdox", completed_at: Time.current)

    duplicate = ChapterProgress.new(user: @user, chapter_id: "05", product_code: "chatdox", completed_at: Time.current)
    assert_not duplicate.valid?
  end

  test "product_code must be a known product code" do
    progress = ChapterProgress.new(user: @user, chapter_id: "05", product_code: "unknown_product", completed_at: Time.current)
    assert_not progress.valid?
    assert_includes progress.errors[:product_code], "is not included in the list"
  end

  test "chapter_id outside 1..20 is rejected" do
    progress = ChapterProgress.new(user: @user, chapter_id: "21", product_code: "chatdox", completed_at: Time.current)
    assert_not progress.valid?
    assert_includes progress.errors[:chapter_id], "is not included in the list"
  end

  test "canonical Chatdox S01 ids are valid but malformed lookalikes are rejected" do
    assert ChapterProgress.new(user: @user, chapter_id: "S01E05", product_code: "chatdox").valid?

    %w[1 001 S01E21].each do |id|
      assert_not ChapterProgress.new(user: @user, chapter_id: id, product_code: "chatdox").valid?
    end
  end

  test "a brand-new Product row is accepted as a valid product_code with no code changes" do
    Product.create!(code: "widget_test", name: "Widget Test", active: true, sale_enabled: false)

    progress = ChapterProgress.new(user: @user, chapter_id: "05", product_code: "widget_test", completed_at: Time.current)
    assert progress.valid?
  end
end
