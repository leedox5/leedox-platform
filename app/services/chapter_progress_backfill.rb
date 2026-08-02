class ChapterProgressBackfill
  Result = Data.define(:dry_run, :scanned, :convertible, :converted, :collisions, :canonical, :unknown) do
    def to_h = members.to_h { |name| [ name, public_send(name) ] }
  end

  def self.call(dry_run: true, batch_size: 500)
    new(dry_run:, batch_size:).call
  end

  def initialize(dry_run:, batch_size:)
    @dry_run = dry_run
    @batch_size = Integer(batch_size)
    @counts = Hash.new(0)
  end

  def call
    scope.in_batches(of: batch_size) do |batch|
      batch.order(:id).each { |progress| process(progress) }
    end

    Result.new(dry_run:, **%i[scanned convertible converted collisions canonical unknown].to_h { |key| [ key, counts[key] ] })
  end

  private

  attr_reader :dry_run, :batch_size, :counts

  def scope
    ChapterProgress.where(product_code: "chatdox")
  end

  def process(progress)
    counts[:scanned] += 1
    identity = ProductContent::ChapterIdentity.normalize(product_code: "chatdox", chapter_id: progress.chapter_id)

    unless identity.supported?
      counts[:unknown] += 1
      return
    end
    if progress.chapter_id == identity.canonical_id
      counts[:canonical] += 1
      return
    end

    counts[:convertible] += 1
    collision = ChapterProgress.exists?(
      user_id: progress.user_id, product_code: "chatdox", chapter_id: identity.canonical_id
    )
    counts[:collisions] += 1 if collision
    return if dry_run

    migrate(progress, identity.canonical_id)
    counts[:converted] += 1
  end

  def migrate(progress, canonical_id)
    ChapterProgress.transaction(requires_new: true) do
      legacy = ChapterProgress.lock.find_by(id: progress.id)
      return unless legacy

      canonical = ChapterProgress.lock.find_by(
        user_id: legacy.user_id, product_code: "chatdox", chapter_id: canonical_id
      )
      if canonical
        canonical.update_columns(
          completed_at: [ canonical.completed_at, legacy.completed_at ].compact.min,
          created_at: [ canonical.created_at, legacy.created_at ].min,
          updated_at: [ canonical.updated_at, legacy.updated_at ].max
        )
        legacy.delete
      else
        legacy.update_columns(chapter_id: canonical_id)
      end
    end
  end
end
