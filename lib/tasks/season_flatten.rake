# Handoff 0065. Run in this order on a database that has the additive migration:
#   bin/rails season_flatten:plan      (nothing is written)
#   bin/rails season_flatten:run       (writes; refuses unless verification passes)
#   bin/rails season_flatten:verify    (read-only, any time afterwards)
#   bin/rails season_flatten:rollback  (undoes the structure, see SeasonFlatten.rollback!)
namespace :season_flatten do
  def print_report(report)
    puts "#{report.dry_run ? 'PLAN (rolled back, nothing written)' : 'RUN (committed)'}: #{report.mappings.size} season(s), verification #{report.verified ? 'PASSED' : 'not reached'}"
    report.mappings.each do |m|
      puts format("  %-28s -> /products/%-28s %s episodes=%-3d status=%s%s", "/products/#{m.old_line_slug}/#{m.old_season_slug}", m.new_slug,
        m.created ? "NEW LINE" : "same line", m.episodes, m.status, m.product_code ? " product=#{m.product_code}" : "")
    end
    report.warnings.each { |warning| puts "  WARNING: #{warning}" }
  end

  desc "Show exactly what the move would do (runs it fully, verifies, then rolls back)"
  task plan: :environment do
    print_report(SeasonFlatten.plan)
  end

  desc "Move Season data onto ProductLine (commits only if the lossless checks pass)"
  task run: :environment do
    print_report(SeasonFlatten.run!)
  end

  desc "Re-check the flattening invariants (read-only)"
  task verify: :environment do
    problems = SeasonFlatten.verify
    puts problems.empty? ? "OK: all invariants hold" : problems.map { |problem| "PROBLEM: #{problem}" }
    exit(1) if problems.any?
  end

  desc "Undo the structure of the move (refuses if products already hold their own episodes)"
  task rollback: :environment do
    SeasonFlatten.rollback!
    puts "rolled back"
  end
end
