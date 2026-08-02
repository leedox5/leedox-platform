namespace :chapter_progress do
  desc "Inventory or backfill Chatdox S01 progress IDs (APPLY=1 mutates; default is dry-run)"
  task backfill_chatdox_s01: :environment do
    result = ChapterProgressBackfill.call(
      dry_run: ENV["APPLY"] != "1",
      batch_size: ENV.fetch("BATCH_SIZE", 500)
    )
    puts result.to_h.map { |key, value| "#{key}=#{value}" }.join(" ")
  end
end
