require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ChatdoxPlatform
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Handoff 0056 R4 -- uploaded files are only ever served through our own
    # authorized download actions (ProductLinesController#asset,
    # Admin::ContentAssetsController#download). Drop Active Storage's built-in
    # blob/representation/direct-upload routes so no signed blob URL can be
    # used to bypass those gates.
    config.active_storage.draw_routes = false

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Asia/Seoul"
    config.i18n.default_locale = :ko
    # Rails/ActiveModel/ActiveRecord/Devise only ship English translations for
    # their own built-in messages (validation errors, etc.) -- this app has no
    # ko.yml coverage for those and isn't attempting to add it. Without a
    # fallback, any of those untranslated lookups would render as
    # "translation missing: ko...." instead of silently staying in English.
    # This must name :en explicitly -- `fallbacks = true` falls back to
    # I18n.default_locale, which is :ko itself now, so it would be a no-op.
    # Has to be set for every environment, not just production, since
    # I18n.locale defaults straight from I18n.default_locale everywhere (the
    # app never sets it per-request).
    config.i18n.fallbacks = [ :en ]
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
