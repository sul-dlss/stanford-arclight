# frozen_string_literal: true

if defined?(Sidekiq) && ENV['SIDEKIQ_REDIS_URL']

  Sidekiq.configure_server do |config|
    config.logger.level = Logger.const_get(ENV.fetch('RAILS_LOG_LEVEL', 'info').upcase.to_s)
    config.redis = { url: ENV.fetch('SIDEKIQ_REDIS_URL') }
  end

  Sidekiq.configure_client do |config|
    config.logger.level = Logger.const_get(ENV.fetch('RAILS_LOG_LEVEL', 'info').upcase.to_s)
    config.redis = { url: ENV.fetch('SIDEKIQ_REDIS_URL') }
  end
end
