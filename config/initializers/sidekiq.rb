# frozen_string_literal: true

Sidekiq.configure_server do |config|
  config.logger.level = Logger.const_get(ENV.fetch('RAILS_LOG_LEVEL', 'info').upcase.to_s)
end
