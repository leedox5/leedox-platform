# Vertical-slice content source (handoff 0053 R2) -- reads chapters from
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
class ProductContent::DatabaseSource
  attr_reader :product_code

  def initialize(product_code)
    @product_code = product_code
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

  private

  def bundles
    ContentBundle.joins(:product).where(products: { code: product_code }).order(:position)
  end

  def episodes
    ContentEpisode.where(bundle_id: bundles.select(:id)).ordered
  end

  def chapter_hash(episode)
    id = episode_id(episode)
    {
      id: id,
      slug: id,
      title: episode.customer_title.presence || episode.internal_ref.presence || "제목 없음",
      product_code: product_code,
      available: episode.published?,
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
