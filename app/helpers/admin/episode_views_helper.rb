# Handoff 0073 R3 -- "12회 · 5명" for an EpisodeView::Stats (nil = nothing counted yet).
module Admin::EpisodeViewsHelper
  def view_stats_label(stats)
    stats ||= EpisodeView::Stats.empty
    "#{number_with_delimiter(stats.views)}회 · #{number_with_delimiter(stats.people)}명"
  end
end
