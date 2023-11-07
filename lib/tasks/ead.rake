# frozen_string_literal: true

require 'fileutils'

# rubocop:disable Metrics/BlockLength
namespace :ead do
  desc 'Download all published EADs in ArchiveSapce to data directory'
  # TODO: Allow harvestable to passed as an argument
  task :download_resources, %i[index updated_after] => :environment do |_task, args|
    args.with_defaults(index: false, updated_after: nil)
    index = args[:index] == 'true'
    harvestable = ENV.fetch('HARVESTABLE_REPOSITORIES').split(' ')

    harvestable.each do |repo_code|
      repository_id = repositories[repo_code]
      resource_uris = client.published_resource_uris(repository_id:, updated_after: args[:updated_after])
      directory = "#{ENV.fetch('DIR', 'data')}/#{repo_code}"

      FileUtils.mkdir_p directory

      resource_uris.each do |resource|
        DownloadEadJob.perform_async(resource['ead_id'], resource['uri'], repo_code, index)
      end
    end
  end

  desc 'Index all EADs in a directory'
  # TODO: Allow indexable repos to passed as an argument or pull from config
  # TODO: Use configured directory as above or fallback to data/
  task index_all: :environment do
    repository = 'eal'
    files = Dir.glob("data/#{repository}/*.xml")
    files.each do |file|
      IndexEadJob.perform_async(file, repository)
    end
  end

  def repositories
    @repositories ||= client.repositories
                            .pluck('repo_code', 'uri')
                            .to_h
                            .transform_keys(&:downcase)
                            .transform_values { |v| v.split('/').last }
  end

  def client
    @client ||= AspaceClient.new
  end
end
