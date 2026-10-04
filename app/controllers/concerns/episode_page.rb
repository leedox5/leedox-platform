# Handoff 0074 -- everything the customer episode page (product_lines/episode) needs, shared by
# ProductLinesController#episode and EpisodeCommentsController (which re-renders the page with
# the rejected comment and its errors). Both include ProductLineGates first, so @product_line,
# @episodes and @current_episode are already loaded and every gate has passed.
module EpisodePage
  extend ActiveSupport::Concern

  private

  def prepare_episode_page
    index = @episodes.index(@current_episode)
    @prev_episode = index.positive? ? @episodes[index - 1] : nil
    @next_episode = @episodes[index + 1]
    @content_html = ContentMarkdown.render(strip_leading_heading(@current_episode.body.to_s), parent: @current_episode)
    @takeaways = @current_episode.content_takeaways.ordered.map do |takeaway|
      { kind: takeaway.kind, body_html: ContentMarkdown.render(takeaway.body.to_s, parent: @current_episode) }
    end
    @assets = @current_episode.content_assets.ordered.with_attached_file
    load_episode_comments
  end

  # The comment thread: top-level comments oldest first, each with its replies oldest first,
  # in two queries (comments + their authors) whatever the size. Customers don't see deleted
  # or hidden comments -- except a top-level one with a visible reply, which stays as a
  # placeholder. Admins also see hidden (not deleted) comments, marked as such (0074 R2); the
  # count is the customers' count for everyone. Best-effort like the view counter (0073): if comments can't be loaded (e.g.
  # the table doesn't exist yet between deploy and migrate) the section is left out and the
  # episode itself still renders.
  def load_episode_comments
    all = @current_episode.episode_comments.order(:created_at, :id).includes(:user).to_a
    replies = all.select(&:reply?).group_by(&:parent_id)
    @comment_threads = all.reject(&:reply?).filter_map do |comment|
      visible_replies = (replies[comment.id] || []).select { |reply| comment_shown?(reply) }
      next unless comment_shown?(comment) || visible_replies.any?

      [ comment, visible_replies ]
    end
    @comment_count = @comment_threads.sum { |comment, visible_replies| (comment.visible? ? 1 : 0) + visible_replies.count(&:visible?) }
  rescue StandardError => e
    Rails.logger.warn("[episode_comments] not loaded: #{e.class}: #{e.message}")
    @comment_threads = nil
  end

  def comment_shown?(comment)
    comment.visible? || (current_user&.admin? && comment.hidden? && !comment.deleted?)
  end

  def strip_leading_heading(raw_markdown)
    raw_markdown.sub(/\A\s*#[^\n]*\n?/, "")
  end
end
