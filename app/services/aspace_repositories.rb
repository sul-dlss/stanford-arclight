# frozen_string_literal: true

# Fetches and transforms repository information from archivesspace
class AspaceRepositories
  class << self
    delegate :all, :all_harvestable, :find_by, to: :instance
  end

  def self.instance
    new
  end

  def all
    Rails.cache.fetch('aspace_repositories', expires_in: 1.hour) do
      Settings.aspace.keys.flat_map do |aspace_config_set|
        client(aspace_config_set).repositories.flat_map do |repo|
          Aspace::Repository.new(**repo.slice('repo_code', 'uri').symbolize_keys, aspace_config_set:)
        end
      end
    end
  end

  def all_harvestable
    all.select(&:harvestable?)
  end

  def find_by(code:, aspace_config_set: :default)
    all.find { |repo| repo.code == code && repo.aspace_config_set == aspace_config_set }
  end

  private

  def client(aspace_config_set)
    AspaceClient.new(aspace_config_set:)
  end
end
