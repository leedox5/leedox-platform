require "test_helper"

# Handoff 0056 R3 / 0065 -- a ContentEpisode belongs to exactly one of a legacy
# ContentBundle or a ProductLine. (product_season_id survives only as the legacy
# pointer of episodes that existed before the flattening.)
class ContentEpisodeParentTest < ActiveSupport::TestCase
  setup do
    @bundle = ContentBundle.create!(internal_name: "legacy")
    @line = ProductLine.create!(internal_name: "A", customer_name: "A", slug: "line-a", introduction: "소개")
  end

  test "an episode with only a bundle is valid and reports it as parent" do
    episode = ContentEpisode.create!(bundle: @bundle, position: 1)
    assert_equal @bundle, episode.parent
  end

  test "an episode with only a product line is valid and reports it as parent" do
    episode = ContentEpisode.create!(product_line: @line, position: 1)
    assert_equal @line, episode.parent
    assert_nil episode.bundle_id
  end

  test "an episode with neither parent is rejected" do
    episode = ContentEpisode.new(position: 1)
    assert_not episode.valid?
    assert_includes episode.errors.full_messages.join, "정확히 하나"
  end

  test "an episode with both a bundle and a product line is rejected" do
    episode = ContentEpisode.new(bundle: @bundle, product_line: @line, position: 1)
    assert_not episode.valid?
    assert_includes episode.errors.full_messages.join, "정확히 하나"
  end

  test "the DB check constraint rejects a bundle-and-line row and a no-parent row even when validations are skipped" do
    assert_raises(ActiveRecord::StatementInvalid) do
      ContentEpisode.new(bundle: @bundle, product_line: @line, position: 1).save!(validate: false)
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      ContentEpisode.new(position: 1).save!(validate: false)
    end
  end

  test "during the transition an episode may carry both the legacy Season pointer and its line; a bundle episode may not carry a Season" do
    season = ProductSeason.create!(product_line: @line, internal_name: "S01", season_code: "S01", slug: "s01")
    both = ContentEpisode.new(product_line: @line, product_season: season, position: 1)
    assert both.save, both.errors.full_messages.to_sentence

    assert_raises(ActiveRecord::StatementInvalid) do
      ContentEpisode.new(bundle: @bundle, product_season: season, position: 1).save!(validate: false)
    end
  end

  test "position is unique within each parent, but a bundle episode and a line episode may share a position" do
    ContentEpisode.create!(bundle: @bundle, position: 1)
    ContentEpisode.create!(product_line: @line, position: 1)

    assert_not ContentEpisode.new(bundle: @bundle, position: 1).valid?
    assert_not ContentEpisode.new(product_line: @line, position: 1).valid?
    assert ContentEpisode.new(bundle: @bundle, position: 2).valid?

    other_line = ProductLine.create!(internal_name: "B", customer_name: "B", slug: "line-b", introduction: "소개")
    assert ContentEpisode.new(product_line: other_line, position: 1).valid?
  end

  test "line episodes keep revisions, takeaways and cascade delete like bundle episodes" do
    episode = ContentEpisode.create!(product_line: @line, position: 1, body: "v1")
    episode.update!(body: "v2")
    episode.content_takeaways.create!(kind: "체크리스트", body: "- [ ] a")
    assert_equal 1, episode.content_revisions.count
    assert_equal "v1", episode.content_revisions.first.body_snapshot

    assert_difference [ "ContentRevision.count", "ContentTakeaway.count" ], -1 do
      episode.destroy!
    end
  end

  test "a product line cannot be destroyed while it still has episodes" do
    @line.content_episodes.create!(position: 1, customer_title: "편")
    assert_not @line.destroy
  end

  test "bundle episodes are unaffected: still ordered, still cascade with their bundle" do
    ContentEpisode.create!(bundle: @bundle, position: 2)
    ContentEpisode.create!(bundle: @bundle, position: 1)
    assert_equal [ 1, 2 ], @bundle.content_episodes.ordered.map(&:position)
    assert_difference "ContentEpisode.count", -2 do
      @bundle.destroy!
    end
  end

  # Handoff 0070 -- the customer product page's "공개 예정" cards read this scope, and only this scope: an
  # episode that's literally draft, not any other not-yet-published status.
  test "the draft scope is exactly status draft, and summary is a free-text, unvalidated field" do
    published = ContentEpisode.create!(product_line: @line, position: 1, status: "published")
    draft = ContentEpisode.create!(product_line: @line, position: 2, status: "draft")
    ContentEpisode.create!(product_line: @line, position: 3, status: "in_review")
    ContentEpisode.create!(product_line: @line, position: 4, status: "unpublished")
    ContentEpisode.create!(product_line: @line, position: 5, status: "archived")

    assert_equal [ draft ], @line.content_episodes.draft.to_a
    assert_not_equal [ draft ], [ published ]

    draft.update!(summary: "일부러 아주 길게 적어본 한 줄 예고 문구입니다 " * 3)
    assert draft.valid?, "no length validation -- a long summary is never rejected"
  end
end
