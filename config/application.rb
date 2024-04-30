require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module StanfordArclight
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks traject))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    config.time_zone = 'Pacific Time (US & Canada)'

    Recaptcha.configure do |config|
      config.site_key = ENV.fetch('RECAPTCHA_SITE_KEY', '6Lc6BAAAAAAAAChqRbQZcn_yyyyyyyyyyyyyyyyy')
      config.secret_key = ENV.fetch('RECAPTCHA_SECRET_KEY', '6Lc6BAAAAAAAAKN3DRm6VA_xxxxxxxxxxxxxxxxx')
    end

    # This folder contains engine overrides
    # Based on https://edgeguides.rubyonrails.org/engines.html#overriding-models-and-controllers
    overrides = Rails.root.join("app/overrides").to_s
    Rails.autoloaders.main.ignore(overrides)

    config.to_prepare do
      Dir.glob("#{overrides}/**/*_override.rb").sort.each do |override|
        load override
      end
    end
  end
end
