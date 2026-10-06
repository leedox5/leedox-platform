# Handoff 0073 -- counts a view of a published episode. Every counted open adds 1 to the
# (episode, viewer, KST day) row's view_count (R3); the row itself is what makes "people" countable.
#
# Runs as an after_action on ProductLinesController#episode, so it only ever sees requests that
# already passed every gate (ProductLineGates: listed-or-reachable line, published episode,
# license for a gated line) and actually rendered the body -- a 404, a sign-in redirect or a
# purchase redirect never reaches it. Recording is best-effort: any error (StandardError, not only database errors -- e.g. the
# table not existing yet between deploy and migrate) is logged and swallowed, so the episode
# page never fails because of a view count.
#
# Admins are counted like any signed-in user (0073 R2) -- only on this customer page; the admin preview
# (Admin::ContentEpisodesController) has no tracking. The gates have no admin bypass, so an admin can't
# reach a draft episode through this URL either.
#
# Not counted: non-GET/HEAD requests, Turbo/browser prefetches (X-Sec-Purpose /
# Sec-Purpose: prefetch), bots (BOT_USER_AGENT, or no User-Agent at all), and episodes of a
# series that isn't listed (unlisted/draft lines).
#
# "Same person": a signed-in user by user id, a guest by a random id kept in the existing
# Rails session cookie. Either is stored only as an HMAC (viewer_key) -- no IP, User-Agent or
# raw user id is written.
#
# 0074 R2 -- the redirect back to the episode after a comment action (post, delete, admin hide/
# unhide) isn't a view. The action sets flash[SKIP_FLASH] = episode id; the very next request
# consumes it (flash lives exactly one request), and only skips counting if it's that episode's
# page. It sits in the encrypted session cookie, so a visitor can't set it from a URL, and it
# can't outlive the redirect to suppress a later ordinary view.
module EpisodeViewTracking
  extend ActiveSupport::Concern

  SKIP_FLASH = :skip_episode_view

  BOT_USER_AGENT = /bot|crawl|spider|slurp|preview|fetch|scrape|facebookexternalhit|embedly|whatsapp|
    kakaotalk-scrap|daumoa|yeti|headless|python-requests|curl|wget|httpclient|okhttp|go-http-client/ix

  private

  def record_episode_view
    return unless countable_episode_view?

    # One statement: INSERT ... ON CONFLICT (uniqueness) DO UPDATE SET view_count = view_count + 1, so two
    # concurrent opens can neither both insert nor lose an increment.
    row = { content_episode_id: @current_episode.id, viewed_on: Date.current, viewer_key: episode_viewer_key, view_count: 1, created_at: Time.current }
    # Handoff 0092 R2 -- whether it was a signed-in member (an 열린 편 is read by guests too). Set on the new row; the
    # (episode, viewer, day) row's viewer is one person, so it can't change. Skipped until the column exists.
    row[:signed_in] = current_user.present? if EpisodeView.column_names.include?("signed_in")
    EpisodeView.upsert(
      row,
      unique_by: EpisodeView::UNIQUENESS,
      on_duplicate: Arel.sql("view_count = episode_views.view_count + 1")
    )
  rescue StandardError => e
    Rails.logger.warn("[episode_views] not recorded: #{e.class}: #{e.message}")
  end

  def countable_episode_view?
    request.get? && !request.head? && response.status == 200 &&
      !prefetch_request? && !bot_request? && flash[SKIP_FLASH] != @current_episode&.id &&
      @current_episode&.published? && @product_line.visibility == "public"
  end

  def prefetch_request?
    [ request.headers["Sec-Purpose"], request.headers["X-Sec-Purpose"], request.headers["Purpose"] ]
      .any? { |value| value.to_s.include?("prefetch") }
  end

  def bot_request?
    user_agent = request.user_agent.to_s
    user_agent.blank? || user_agent.match?(BOT_USER_AGENT)
  end

  def episode_viewer_key
    identity = if current_user
      "user:#{current_user.id}"
    else
      "guest:#{session[:episode_visitor_id] ||= SecureRandom.hex(16)}"
    end
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.key_generator.generate_key("episode_views"), identity).first(32)
  end
end
