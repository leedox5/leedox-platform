# Handoff 0074 -- everything the customer episode page (product_lines/episode) needs, shared by
# ProductLinesController#episode and EpisodeCommentsController (which re-renders the page with
# the rejected comment and its errors). Both include ProductLineGates first, so @product_line,
# @episodes and @current_episode are already loaded and every gate has passed.
module EpisodePage
  extend ActiveSupport::Concern

  # Handoff 0105 -- the 길잡이 줄 (sticky table of contents) shows from this many body h2s up.
  TOC_MIN_SECTIONS = 3

  private

  def prepare_episode_page
    index = @episodes.index(@current_episode)
    @prev_episode = index.positive? ? @episodes[index - 1] : nil
    @next_episode = @episodes[index + 1]
    @content_html, @episode_sections = with_section_ids(
      ContentMarkdown.render(strip_leading_heading(@current_episode.body.to_s), parent: @current_episode))
    @takeaways = @current_episode.content_takeaways.ordered.map do |takeaway|
      { kind: takeaway.kind, body_html: ContentMarkdown.render(takeaway.body.to_s, parent: @current_episode) }
    end
    @assets = @current_episode.content_assets.ordered.with_attached_file
    # Handoff 0092 R2 -- on an 열린 편 without the license: the body only; files and comments become one line each
    # (the view), and only the comment count is shown.
    @full_episode_access = full_episode_access?
    load_episode_comments
  end

  # Handoff 0105 -- every top-level h2 of the body gets id="section-N" (its order, not its words, so editing a heading
  # doesn't break a link to it), and [[id, heading text], ...] feeds the 길잡이 줄. Only the customer episode page does
  # this -- ContentMarkdown (shared with the guide introduction, the admin preview and notices) still drops ids.
  # Takeaways are rendered separately, so their headings are never counted.
  def with_section_ids(html)
    fragment = Nokogiri::HTML5.fragment(html)
    headings = fragment.children.select { |node| node.element? && node.name == "h2" }
    return [ html, [] ] if headings.empty?

    sections = headings.each_with_index.map do |heading, index|
      heading["id"] = "section-#{index + 1}"
      [ heading["id"], heading.text.squish ]
    end
    [ fragment.to_html.html_safe, sections ]
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
