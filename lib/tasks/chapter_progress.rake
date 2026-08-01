namespace :chapter_progress do
  desc "Inventory or backfill Chatdox S01 progress IDs (APPLY=1 mutates; default is dry-run)"
  task backfill_chatdox_s01: :environment do
    applying = ENV["APPLY"] == "1"
    abort "APPLY=1 requires CONFIRM_PRODUCTION=1" if applying && ENV["CONFIRM_PRODUCTION"] != "1"

    result = ChapterProgressBackfill.call(
      dry_run: !applying,
      batch_size: ENV.fetch("BATCH_SIZE", 500)
    )
    puts JSON.generate(result.to_h)
  end
end
