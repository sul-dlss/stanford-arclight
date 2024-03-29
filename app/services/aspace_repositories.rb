# frozen_string_literal: true

# Fetches and transforms repository information from archivesspace
class AspaceRepositories
  class << self
    delegate :all, :all_harvestable, :find_by, to: :instance
  end

  def self.instance
    new
  end

  # Returns values like { 'ars' => '11', 'sul' => '1' }
  # where each key is an aspace repository code and the value
  # is the corresponding aspace repository id
  def all
    @all ||= client.repositories
                   .pluck('repo_code', 'uri')
                   .to_h
                   .transform_keys(&:downcase)
                   .transform_values { |v| v.split('/').last }
  end

  def all_harvestable
    all.slice(*Settings.aspace.harvestable_repository_codes)
  end

  def find_by(code:)
    all[code]
  end

  private

  def client
    @client ||= AspaceClient.new
  end
end
