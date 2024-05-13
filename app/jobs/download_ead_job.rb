# frozen_string_literal: true

##
# Background job to download an EAD XML file from ArchiveSpace
class DownloadEadJob < ApplicationJob
  # By default this will enqueue all harvestable repositories updated since (and including) yesterday
  # Intended as a convenience method for use in a cron job
  # @param updated_after [String] YYYY-MM-DD limit the response to resources updated after a specific date
  def self.enqueue_all_updated(updated_after: (Time.zone.now - 2.days).strftime('%Y-%m-%d'))
    enqueue_all(updated_after:, check_component_dates: true)
  end

  # @param updated_after [String] YYYY-MM-DD optionally limit the response to resources updated after a specific date
  # @param data_dir [String] the path where the file should be saved, such as '/opt/app/arclight/data/ars'
  # @param index [Boolean] if true an IndexEadJob will be queued up with the downloaded file
  # @param generate_pdf [Boolean] if true a GeneratePdfJob will be queued up with the downloaded file
  # @param check_component_dates [Boolean] if true, component level modified dates will be checked
  def self.enqueue_all(updated_after: nil, data_dir: Settings.data_dir, index: true,
                       generate_pdf: Settings.pdf_generation.create_on_ead_download, check_component_dates: false)
    create_directories(data_dir:)
    AspaceRepositories.all_harvestable.each do |repository|
      enqueue_repository(repository:, updated_after:, data_dir:, index:, generate_pdf:, check_component_dates:)
    end
  end

  # @example DownloadEadJob.enqueue_one_by(aspace_repository_code: 'ars')
  # @param aspace_repository_code [String] the repository code in ArchivesSpace, such as 'ars'
  # @param updated_after [String] YYYY-MM-DD optionally limit the response to resources updated after a specific date
  # @param data_dir [String] the path where the file should be saved, such as '/opt/app/arclight/data/ars'
  # @param index [Boolean] if true an IndexEadJob will be queued up with the downloaded file
  # @param generate_pdf [Boolean] if true a GeneratePdfJob will be queued up with the downloaded file
  def self.enqueue_one_by(aspace_repository_code:, updated_after: nil,
                          data_dir: Settings.data_dir, index: true,
                          generate_pdf: Settings.pdf_generation.create_on_ead_download)
    create_directories(data_dir:)
    repository = AspaceRepositories.find_by(code: aspace_repository_code)
    enqueue_repository(repository:, updated_after:, data_dir:, index:, generate_pdf:)
  end

  # rubocop:disable Metrics/ParameterLists
  def self.enqueue_repository(repository:, updated_after:, data_dir:, index:, generate_pdf:,
                              check_component_dates: false)
    uris_to_exclude = []

    repository.each_published_resource(updated_after:) do |resource|
      uris_to_exclude << resource.uri if check_component_dates
      enqueue_resource(resource:, data_dir:, index:, generate_pdf:)
    end

    return unless check_component_dates

    repository.each_published_resource_with_updated_components(updated_after:, uris_to_exclude:) do |resource|
      enqueue_resource(resource:, index:, data_dir:, generate_pdf:)
    end
  end
  private_class_method :enqueue_repository
  # rubocop:enable Metrics/ParameterLists

  def self.enqueue_resource(resource:, data_dir:, index:, generate_pdf:)
    file_dir = "#{data_dir}/#{resource.arclight_repository_code}"
    DownloadEadJob.perform_later(resource_uri: resource.uri, file_name: resource.file_name,
                                 file_dir:, index:, generate_pdf:)
  end
  private_class_method :enqueue_resource

  # Ensure all arclight repositories have a directory where EAD files can be stored
  def self.create_directories(data_dir:)
    Arclight::Repository.all.map(&:slug).each do |slug|
      FileUtils.mkdir_p "#{data_dir}/#{slug}"
    end
  end
  private_class_method :create_directories

  # @example DownloadEadJob.perform_later(resource_uri: '/repositories/2/resources/5363',
  #                                       file_name: 'ars0018',
  #                                       file_dir: '/opt/app/arclight/data/ars' )
  # @param resource_uri [String] the URI of the resource in ArchivesSpace, such as '/repositories/2/resources/5363'
  # @param file_name [String] the name of the file to be created, such as 'ead1234'
  # @param file_dir [String] the path where the file should be saved, such as '/opt/app/arclight/data/ars'
  #        the directory specified must already exist
  # @param index [Boolean] if true an IndexEadJob will be queued up with the downloaded file
  # @param generate_pdf [Boolean] if true a GeneratePdfJob will be queued up with the downloaded file
  def perform(resource_uri:, file_name:, file_dir:, index: false,
              generate_pdf: Settings.pdf_generation.create_on_ead_download)
    ead_xml = AspaceClient.new.resource_description(resource_uri)
    file_path = File.join(file_dir, "#{file_name}.xml")

    File.open(file_path, 'wb') do |f|
      ead = Nokogiri::XML(ead_xml, &:noblanks)
      f.puts ead.to_xml(indent: 2)
    end

    IndexEadJob.perform_later(file_path:, resource_uri:) if index
    GeneratePdfJob.perform_later(file_path:, file_name:, data_dir: file_dir, skip_existing: false) if generate_pdf
  end
end
