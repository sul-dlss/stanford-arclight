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
      enqueue(aspace_repository_id: repository.id, aspace_repository_code: repository.code, updated_after:,
              data_dir:, index:, generate_pdf:, check_component_dates:)
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
    aspace_repository_id = AspaceRepositories.find_by(code: aspace_repository_code).id
    enqueue(aspace_repository_id:, aspace_repository_code:, updated_after:, data_dir:, index:, generate_pdf:)
  end

  # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength
  def self.enqueue(aspace_repository_id:, aspace_repository_code:, updated_after:, data_dir:, index:, generate_pdf:,
                   check_component_dates: false)
    aspace = AspaceClient.new
    resource_uris = aspace.published_resource_uris(repository_id: aspace_repository_id, updated_after:)
    uris_to_exclude = []

    resource_uris.each do |resource|
      uris_to_exclude << resource['uri'] if check_component_dates
      enqueue_resource(aspace_repository_code:, ead_id: resource['ead_id'], resource_uri: resource['uri'],
                       data_dir:, index:, generate_pdf:)
    end

    return unless check_component_dates

    aspace.published_resource_with_updated_component_uris(
      repository_id: aspace_repository_id, updated_after:, uris_to_exclude:
    ).each do |resource|
      enqueue_resource(aspace_repository_code:, ead_id: resource['ead_id'],
                       resource_uri: resource['uri'], index:, data_dir:, generate_pdf:)
    end
  end
  private_class_method :enqueue
  # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength

  # rubocop:disable Metrics/ParameterLists
  def self.enqueue_resource(aspace_repository_code:, ead_id:, resource_uri:, data_dir:, index:, generate_pdf:)
    arclight_repository_code = ArclightRepositoryMapper.map_to_code(aspace_repository_code:, ead_id:)
    directory = "#{data_dir}/#{arclight_repository_code}"
    DownloadEadJob.perform_later(resource_uri:, file_name: ead_id, data_dir: directory, index:, generate_pdf:)
  end
  private_class_method :enqueue_resource
  # rubocop:enable Metrics/ParameterLists

  # Ensure all arclight repositories have a directory where EAD files can be stored
  def self.create_directories(data_dir:)
    Arclight::Repository.all.map(&:slug).each do |slug|
      FileUtils.mkdir_p "#{data_dir}/#{slug}"
    end
  end
  private_class_method :create_directories

  # @example DownloadEadJob.perform_later(resource_uri: '/repositories/2/resources/5363',
  #                                       file_name: 'ars0018',
  #                                       data_dir: '/opt/app/arclight/data/ars' )
  # @param resource_uri [String] the URI of the resource in ArchivesSpace, such as '/repositories/2/resources/5363'
  # @param file_name [String] the name of the file to be created, such as 'ead1234'
  # @param data_dir [String] the path where the file should be saved, such as '/opt/app/arclight/data/ars'
  #        the directory specified must already exist
  # @param index [Boolean] if true an IndexEadJob will be queued up with the downloaded file
  # @param generate_pdf [Boolean] if true a GeneratePdfJob will be queued up with the downloaded file
  def perform(resource_uri:, file_name:, data_dir:, index: false,
              generate_pdf: Settings.pdf_generation.create_on_ead_download)
    ead_xml = AspaceClient.new.resource_description(resource_uri)

    # Takes a supplied file name like 'abc 123/ABC.XML' and turns it into: 'abc-123-abc.xml'
    xml_file_name = file_name.sub(/(\.xml)?$/i, '').parameterize.concat('.xml')
    file_path = File.join(data_dir, xml_file_name.to_s)

    File.open(file_path, 'wb') do |f|
      ead = Nokogiri::XML(ead_xml, &:noblanks)
      f.puts ead.to_xml(indent: 2)
    end

    IndexEadJob.perform_later(file_path:, resource_uri:) if index
    GeneratePdfJob.perform_later(file_path:, file_name: xml_file_name, data_dir:, skip_existing: false) if generate_pdf
  end
end
