namespace :chatdox do
  namespace :readiness_preview do
    EMAIL = "chatdox-0010-readiness@example.invalid"

    desc "Create an isolated admin for local production-like readiness preview"
    task setup: :environment do
      abort "local preview only" if ENV["RAILWAY_ENVIRONMENT"].present?
      abort "set CONFIRM_LOCAL=1" unless ENV["CONFIRM_LOCAL"] == "1"
      password = ENV.fetch("PREVIEW_PASSWORD")
      abort "PREVIEW_PASSWORD must be at least 12 characters" if password.length < 12

      user = User.find_or_initialize_by(email: EMAIL)
      user.assign_attributes(name: "0010 Readiness Preview", role: :admin, password:, password_confirmation: password)
      user.save!
      puts "preview_email=#{EMAIL}"
      puts "password_source=PREVIEW_PASSWORD"
    end

    desc "Remove only the isolated local readiness preview admin"
    task cleanup: :environment do
      abort "local preview only" if ENV["RAILWAY_ENVIRONMENT"].present?
      User.where(email: EMAIL).delete_all
      puts "preview_removed=true"
    end
  end
end
