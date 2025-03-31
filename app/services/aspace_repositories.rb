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
    Settings.aspace.keys.flat_map do |aspace_config_set|
      client(aspace_config_set).repositories.flat_map do |repo|
        Aspace::Repository.new(**repo.slice('repo_code', 'uri').symbolize_keys, aspace_config_set:)
      end
    end
  end

  def all_harvestable
    all.select(&:harvestable?)
  end

  def find_by(code:)
    all.find { |repo| repo.code == code }
  end

  private

  def client(aspace_config_set)
    AspaceClient.new(aspace_config_set:)
  end
end
