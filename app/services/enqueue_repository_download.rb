# frozen_string_literal: true

# Service to enqueue jobs to download EADs from an Aspace repository
class EnqueueRepositoryDownload
  attr_reader :repository, :config

  # @param repository [Aspace::Repository] the repository to be downloaded
  # @param config [DownloadEadJob::Config] sets the options for the download
  def initialize(repository:, config:)
    @repository = repository
    @config = config
  end

  def self.call(repository:, config:)
    new(repository:, config:).enqueue_repository
  end

  def enqueue_repository
    uris_to_exclude = []
    repository.each_published_resource(updated_after: config.updated_after) do |resource|
      uris_to_exclude << resource.uri if config.check_record_dates
      enqueue_resource(resource:)
    end

    check_for_updated_components_and_agents(uris_to_exclude:)
  end

  private

  def check_for_updated_components_and_agents(uris_to_exclude:)
    return unless config.check_record_dates

    # Normally we want to check if components or agents have been updated
    # and only enqueue resources that would be impacted by these updates.
    # However, if a large number of resources, agents or components have been updated
    # these queries become too large and exceed ASpace Solr's max boolean clause limits.
    # If we encounter this case it means a large number of resources have been updated, so
    # we switch to a fallback strategy of downloading all resources in the repository.
    enqueue_resources_with_updated_components(uris_to_exclude:)
    enqueue_resources_with_updated_agents(uris_to_exclude:)
  rescue ArgumentError => e
    fallback_enqueuing_strategy_warning(e)
    enqueue_all_resources_except_already_downloaded(uris_to_exclude:)
  end

  def fallback_enqueuing_strategy_warning(error)
    message = 'ArgumentError while queueing repository for download. ' \
              'Instead of trying to find changed resources we will download all of them ' \
              "except ones we have already downloaded. Error: #{error}"
    Rails.logger.warn(message)
    Honeybadger.notify(message)
  end

  def enqueue_all_resources_except_already_downloaded(uris_to_exclude:)
    repository.each_published_resource do |resource|
      next if uris_to_exclude.include?(resource.uri)

      enqueue_resource(resource:)
    end
  end

  def enqueue_resources_with_updated_components(uris_to_exclude:)
    repository.each_published_resource_with_updated_components(updated_after: config.updated_after,
                                                               uris_to_exclude:) do |resource|
      enqueue_resource(resource:)
    end
  end

  def enqueue_resources_with_updated_agents(uris_to_exclude:)
    repository.each_published_resource_with_updated_agents(updated_after: config.updated_after,
                                                           uris_to_exclude:) do |resource|
      enqueue_resource(resource:)
    end
  end

  def enqueue_resource(resource:)
    DownloadEadJob.perform_later(aspace_config_set: repository.aspace_config_set,
                                 resource_uri: resource.uri,
                                 file_name: resource.file_name, file_dir: file_dir(resource:),
                                 index: config.index, generate_pdf: config.generate_pdf)
  rescue Aspace::AspaceResourceError => e
    message = "Failed to create filename for #{resource.uri}: #{e.message}"
    Rails.logger.warn(message)
    Honeybadger.notify(message)
  end

  def file_dir(resource:)
    "#{config.data_directory}/#{resource.arclight_repository_code}"
  end
end
