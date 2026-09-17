# Vertical-slice content source (handoff 0053 R2/R3) -- reads chapters from
# ContentBundle/ContentEpisode instead of scanning hq/<product_code>/*.md.
# Registered explicitly in ProductContent.registry (same pattern as
# ChatdoxLegacySource) rather than picked up automatically, since an
# unregistered product code still falls back to FilesystemSource.
#
# Deliberately license-only: guest/trial preview in DocPolicy assumes access
# is monotonic in a numeric chapter number (see FilesystemSource, handoff
# 0053 result.md §2.2-B/§9), which doesn't hold for freely-ordered episodes.
# Returning a negative guest/trial limit here disables both previews rather
# than reusing that numeric assumption.
#
# #chapters/#find only ever see `status: "published"` episodes (R3 §5 --
# draft/unpublished must be invisible from the customer path entirely, not
# just blocked on single-episode fetch). Admin preview of a draft is a
# completely separate code path (Admin::ContentEpisodesController#show)
# that never touches this class, so there's no query-param or mode flag
# here that could leak a draft to a non-admin request.
class ProductContent::DatabaseSource
  attr_reader :product_code

  def initialize(product_code)
    @product_code = product_code
  end

  # Guards every query below against a real gap found in R3 review: this
  # class's code can be deployed (registered in ProductContent.registry)
  # before its migration has actually run against a given database -- e.g.
  # production right now, where "content_lab" is registered but
  # content_bundles/content_episodes don't exist yet. Without this,
  # #chapters/#find would raise ActiveRecord::StatementInvalid (undefined
  # table) on any direct request, a 500 rather than the same 404 an
  # unregistered or empty product already gets. table_exists? is a cheap
  # schema-cache check, not a query against the table itself, so it's safe
  # to call even when the table genuinely doesn't exist.
  def self.tables_ready?
    ActiveRecord::Base.connection.table_exists?(:content_bundles) &&
      ActiveRecord::Base.connection.table_exists?(:content_episodes)
  end

  def path
    nil
  end

  def images_path
    nil
  end

  def chapters
    episodes.map { |episode| chapter_hash(episode) }
  end

  def find(id)
    id_str = id.to_s
    chapters.find { |chapter| chapter[:id] == id_str || chapter[:id] == id_str.rjust(2, "0") }
  end

  def phases
    []
  end

  def licensed_chapter_ranges
    [ 1..9999 ]
  end

  def guest_chapter_limit
    -1
  end

  def trial_chapter_limit
    -1
  end

  def missing_chapter_message
    "아직 공개되지 않은 콘텐츠입니다."
  end

  def editorial_status(id)
    episode = episode_for(id)
    return :missing unless episode

    episode.published? ? :written : :draft
  end

  def last_updated_at(slug)
    episode_for(slug)&.updated_at || Time.current
  end

  def theme
    { accent: "blue", label: nil, back_link_label: "목차", index_heading: nil }
  end

  # Counterpart to FilesystemSource reading File.read(path/"#{slug}.md") --
  # see ProductContentController#show, which calls this instead of touching
  # the filesystem directly (handoff 0053 result.md §2.2-A).
  def body(slug)
    episode_for(slug)&.body
  end

  # See ProductContent's interface comment -- FilesystemSource/
  # ChatdoxLegacySource return [] here (no takeaway concept for them).
  def takeaways(slug)
    episode = episode_for(slug)
    return [] unless episode

    episode.content_takeaways.ordered.map do |takeaway|
      { kind: takeaway.kind, body: takeaway.body }
    end
  end

  private

  def bundles
    ContentBundle.joins(:product).where(products: { code: product_code }).order(:position)
  end

  # Only published episodes are visible through this source at all -- there
  # is no "available: false but listed" state for DB content (unlike
  # FilesystemSource, where a registered-but-unwritten chapter can still show
  # up grayed out). Admins preview drafts through a separate controller
  # (Admin::ContentEpisodesController#show) that queries ContentEpisode
  # directly instead of going through ProductContent.
  def episodes
    return ContentEpisode.none unless self.class.tables_ready?

    ContentEpisode.where(bundle_id: bundles.select(:id)).published.ordered
  end

  def chapter_hash(episode)
    id = episode_id(episode)
    {
      id: id,
      slug: id,
      title: episode.customer_title.presence || episode.internal_ref.presence || "제목 없음",
      product_code: product_code,
      available: true,
      kind: :chapter
    }
  end

  def episode_id(episode)
    episode.position.to_s.rjust(2, "0")
  end

  def episode_for(id)
    id_str = id.to_s
    episodes.find { |episode| episode_id(episode) == id_str || episode_id(episode) == id_str.rjust(2, "0") }
  end
end
