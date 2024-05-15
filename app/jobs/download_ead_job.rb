# frozen_string_literal: true

##
# Background job to download an EAD XML file from ArchiveSpace
class DownloadEadJob < ApplicationJob
  # Configures a download.
  class Config
    attr_reader :updated_after, :data_directory, :generate_pdf, :index, :check_record_dates

    # @example DownloadEadJob::Config.new(updated_after: '2024-05-10', check_record_dates: true)
    # @param updated_after [String] YYYY-MM-DD optionally limit the downloads by updated date
    # @param data_directory [String] sets the directory where the files will be saved
    # @param generate_pdf [Boolean] if true a job to generate a PDF file will be enqueued
    # @param index [Boolean] if true a job to index the EAD file will be enqueued
    # @param check_record_dates [Boolean] if true the query will check whether records
    #        (e.g., archival objects, linked agents) have been published/unpublished.
    #        Probably only useful with the updated_after param.
    def initialize(updated_after: nil,
                   data_directory: Settings.data_dir,
                   generate_pdf: Settings.pdf_generation.create_on_ead_download,
                   index: true,
                   check_record_dates: false)

      @updated_after = updated_after
      @data_directory = data_directory
      @generate_pdf = generate_pdf
      @index = index
      @check_record_dates = check_record_dates
    end
  end

  # By default this will enqueue all harvestable repositories updated since (and including) yesterday.
  # Intended as a convenience method for use in a daily cron job.
  # @example DownloadEadJob.enqueue_all_updated(updated_after: '2024-05-10')
  # @param updated_after [String] YYYY-MM-DD limit the response to resources updated after a specific date
  def self.enqueue_all_updated(updated_after: (Time.zone.now - 2.days).strftime('%Y-%m-%d'))
    enqueue_all(config: DownloadEadJob::Config.new(updated_after:, check_record_dates: true))
  end

  # This will enqueue all harvestable repositories.
  # @example DownloadEadJob.enqueue_all
  # @param config [DownloadEadJob::Config] holds configurations for the download
  def self.enqueue_all(config: DownloadEadJob::Config.new)
    create_directories(data_dir: config.data_directory)
    AspaceRepositories.all_harvestable.each { |repository| enqueue_repository(repository:, config:) }
  end

  # This will enqueue one repository selected by its aspace repository code.
  # @example DownloadEadJob.enqueue_one_by(aspace_repository_code: 'ars')
  # @param aspace_repository_code [String] the repository code in ArchivesSpace, such as 'ars'
  # @param config [DownloadEadJob::Config] holds configurations for the download
  def self.enqueue_one_by(aspace_repository_code:, config: DownloadEadJob::Config.new)
    create_directories(data_dir: config.data_directory)
    repository = AspaceRepositories.find_by(code: aspace_repository_code)
    enqueue_repository(repository:, config:)
  end

  # rubocop:disable Metrics/MethodLength
  def self.enqueue_repository(repository:, config:)
    uris_to_exclude = []

    repository.each_published_resource(updated_after: config.updated_after) do |resource|
      uris_to_exclude << resource.uri if config.check_record_dates
      enqueue_resource(resource:, config:)
    end

    return unless config.check_record_dates

    repository.each_published_resource_with_updated_components(updated_after: config.updated_after,
                                                               uris_to_exclude:) do |resource|
      enqueue_resource(resource:, config:)
    end

    repository.each_published_resource_with_updated_agents(updated_after: config.updated_after,
                                                           uris_to_exclude:) do |resource|
      enqueue_resource(resource:, config:)
    end
  end
  # rubocop:enable Metrics/MethodLength
  private_class_method :enqueue_repository

  def self.enqueue_resource(resource:, config:)
    file_dir = "#{config.data_directory}/#{resource.arclight_repository_code}"
    DownloadEadJob.perform_later(resource_uri: resource.uri,
                                 file_name: resource.file_name,
                                 file_dir:, index: config.index,
                                 generate_pdf: config.generate_pdf)
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
  #                                       file_dir: '/opt/app/arclight/data/ars'
  #                                       index: true,
  #                                       generate_pdf: false)
  # @param resource_uri [String] the URI of the resource in ArchivesSpace, such as '/repositories/2/resources/5363'
  # @param file_name [String] the name of the file to be created, such as 'ead1234'
  # @param file_dir [String] the path where the file should be saved, such as '/opt/app/arclight/data/ars'
  #        the directory specified must already exist
  # @param index [Boolean] if true an IndexEadJob will be queued up with the downloaded file
  # @param generate_pdf [Boolean] if true a GeneratePdfJob will be queued up with the downloaded file
  def perform(resource_uri:, file_name:, file_dir:, index:, generate_pdf:)
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
