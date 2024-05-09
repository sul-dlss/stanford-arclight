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
    @all ||= client.repositories.map do |repo|
      Aspace::Repository.new(**repo.slice('repo_code', 'uri').symbolize_keys)
    end
  end

  def all_harvestable
    all.select(&:harvestable?)
  end

  def find_by(code:)
    all.find { |repo| repo.code == code }
  end

  private

  def client
    @client ||= AspaceClient.new
  end
end
