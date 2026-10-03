# Handoff 0073 -- one row per (episode, viewer, KST day); view_count is how many times that viewer
# opened the episode that day (R3: every open counts, no time-window merging). The unique index
# (content_episode_id, viewed_on, viewer_key) plus a single upsert (EpisodeViewTracking) keeps the
# count exact under concurrent requests. Two numbers come out of it:
#   views  = SUM(view_count)
#   people = COUNT(DISTINCT viewer_key) -- for a series, across all its episodes (someone who saw
#            three episodes is one person, not three)
# Admin-only numbers -- nothing customer-facing reads this.
class EpisodeView < ApplicationRecord
  RECENT_DAYS = 7
  UNIQUENESS = %i[content_episode_id viewed_on viewer_key].freeze

  Stats = Data.define(:views, :people) do
    def self.empty = new(views: 0, people: 0)
  end

  belongs_to :content_episode

  # { total: { episode_id => Stats }, recent: { ... } } -- all time and the last RECENT_DAYS days
  # (today included). Four grouped queries, whatever the number of episodes.
  def self.stats_by_episode(episode_ids, today: Date.current)
    grouped_stats(where(content_episode_id: episode_ids), :content_episode_id, today)
  end

  # Same per series ({ product_line_id => Stats }).
  def self.stats_by_product_line(product_line_ids, today: Date.current)
    scope = joins(:content_episode).where(content_episodes: { product_line_id: product_line_ids })
    grouped_stats(scope, "content_episodes.product_line_id", today)
  end

  # The first day anything was counted -- shown in the admin note so it's clear nothing
  # before it exists. nil until the first view.
  def self.counting_since
    minimum(:viewed_on)
  end

  def self.recent_range(today)
    (today - (RECENT_DAYS - 1))..today
  end

  def self.grouped_stats(scope, key, today)
    { total: stats_for(scope, key), recent: stats_for(scope.where(viewed_on: recent_range(today)), key) }
  end

  def self.stats_for(scope, key)
    views = scope.group(key).sum(:view_count)
    people = scope.group(key).distinct.count(:viewer_key)
    views.to_h { |id, count| [ id, Stats.new(views: count, people: people.fetch(id, 0)) ] }
  end
  private_class_method :grouped_stats, :stats_for
end
