# frozen_string_literal: true

require 'okcomputer'

OkComputer.mount_at = 'status'
OkComputer.check_in_parallel = true

# Check if the ASpace client is available
class AspaceClientCheck < OkComputer::Check
  def initialize(aspace_config_set: :default) # rubocop:disable Lint/MissingSuper
    @aspace_config_set = aspace_config_set
  end

  attr_reader :aspace_config_set

  def check
    if AspaceClient.new(aspace_config_set:).ping
      mark_message 'Connected to ASpace Client'
    else
      mark_failure
      mark_message 'Unable to connect to ASpace Client'
    end
  end
end

# Optional checks
OkComputer::Registry.register 'aspace_chs', AspaceClientCheck.new(aspace_config_set: :chs)
OkComputer::Registry.register 'aspace_default', AspaceClientCheck.new(aspace_config_set: :default)
OkComputer::Registry.register 'background_jobs', OkComputer::SidekiqLatencyCheck.new('default', 25)
OkComputer::Registry.register 'directory', OkComputer::DirectoryCheck.new(Settings.data_dir)
OkComputer::Registry.register 'hours_api', OkComputer::HttpCheck.new("#{Settings.hours_api}/status")
OkComputer::Registry.register 'redis', OkComputer::RedisCheck.new(url: ENV.fetch('SIDEKIQ_REDIS_URL',
                                                                                 'redis://localhost:6379/0'))
OkComputer.make_optional %w[aspace_chs aspace_default background_jobs directory hours_api redis]
