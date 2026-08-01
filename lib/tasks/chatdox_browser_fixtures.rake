namespace :chatdox do
  namespace :browser_fixtures do
    EMAILS = {
      trial: "chatdox-0008-trial@example.invalid",
      expired: "chatdox-0008-expired@example.invalid",
      licensed: "chatdox-0008-licensed@example.invalid",
      partial: "chatdox-0008-partial@example.invalid",
      complete: "chatdox-0008-complete@example.invalid",
      collision: "chatdox-0008-collision@example.invalid"
    }.freeze

    desc "Create isolated development accounts for the 0008 browser checklist"
    task setup: :environment do
      abort "development only" unless Rails.env.development?
      abort "set CONFIRM_LOCAL=1" unless ENV["CONFIRM_LOCAL"] == "1"
      password = ENV.fetch("FIXTURE_PASSWORD")
      abort "FIXTURE_PASSWORD must be at least 12 characters" if password.length < 12

      Commerce::CatalogBootstrap.call!
      users = EMAILS.to_h do |state, email|
        user = User.find_or_initialize_by(email:)
        user.assign_attributes(name: "0008 #{state.to_s.titleize}", password:, password_confirmation: password)
        user.save!
        [ state, user ]
      end
      users[:expired].update_columns(created_at: 8.days.ago)

      product = Product.find_by!(code: "chatdox")
      today = Time.zone.today
      end_date = today + 31.days
      License.find_or_create_by!(user: users[:licensed], product:, source: "legacy", starts_on: today) do |license|
        license.status = "active"
        license.last_usable_on = today + 30.days
        license.access_ends_at = License::KST.local(end_date.year, end_date.month, end_date.day)
      end

      completions = {
        partial: %w[S01E01 S01E02],
        complete: (1..20).map { |number| format("S01E%02d", number) },
        collision: %w[01 S01E01]
      }
      completions.each do |state, ids|
        ids.each do |chapter_id|
          ChapterProgress.find_or_create_by!(user: users.fetch(state), product_code: "chatdox", chapter_id:) do |progress|
            progress.completed_at = Time.current
          end
        end
      end

      puts "Created 0008 local fixtures:"
      EMAILS.each { |state, email| puts "#{state}=#{email}" }
      puts "Password was read from FIXTURE_PASSWORD and was not printed."
    end

    desc "Remove only the isolated 0008 development fixture accounts"
    task cleanup: :environment do
      abort "development only" unless Rails.env.development?
      users = User.where(email: EMAILS.values)
      ChapterProgress.where(user_id: users.select(:id)).delete_all
      License.where(user_id: users.select(:id)).delete_all
      users.delete_all
      puts "Removed 0008 local fixtures."
    end
  end
end
