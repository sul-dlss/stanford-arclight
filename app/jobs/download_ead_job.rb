# frozen_string_literal: true

##
# Background job to download an EAD XML file from ArchiveSpace
class DownloadEadJob < ApplicationJob
  # By default this will enqueue all harvestable repositories updated since (and including) yesterday
  # Intended as a convenience method for use in a cron job
  # @param updated_after [String] YYYY-MM-DD limit the response to resources updated after a specific date
  def self.enqueue_all_updated(updated_after: (Time.zone.now - 2.days).strftime('%Y-%m-%d'))
    enqueue_all(updated_after:)
  end

  # @param updated_after [String] YYYY-MM-DD optionally limit the response to resources updated after a specific date
  # @param data_dir [String] the path where the file should be saved, such as '/opt/app/arclight/data/ars'
  # @param index [Boolean] if true an IndexEadJob will be queued up with the downloaded file
  def self.enqueue_all(updated_after: nil, data_dir: ENV.fetch('DATA_DIR', 'data'), index: true)
    create_directories(data_dir:)
    AspaceRepositories.all_harvestable.each do |aspace_repository_code, aspace_repository_id|
      enqueue(aspace_repository_id:, aspace_repository_code:, updated_after:, data_dir:, index:)
    end
  end

  # @example DownloadEadJob.enqueue_one_by(aspace_repository_code: 'ars')
  # @param aspace_repository_code [String] the repository code in ArchivesSpace, such as 'ars'
  # @param updated_after [String] YYYY-MM-DD optionally limit the response to resources updated after a specific date
  # @param data_dir [String] the path where the file should be saved, such as '/opt/app/arclight/data/ars'
  # @param index [Boolean] if true an IndexEadJob will be queued up with the downloaded file
  def self.enqueue_one_by(aspace_repository_code:, updated_after: nil,
                          data_dir: ENV.fetch('DATA_DIR', 'data'), index: true)
    create_directories(data_dir:)
    aspace_repository_id = AspaceRepositories.find_by(code: aspace_repository_code)
    enqueue(aspace_repository_id:, aspace_repository_code:, updated_after:, data_dir:, index:)
  end

  def self.enqueue(aspace_repository_id:, aspace_repository_code:, updated_after:, data_dir:, index:)
    resource_uris = AspaceClient.new.published_resource_uris(repository_id: aspace_repository_id, updated_after:)
    resource_uris.each do |resource|
      arclight_repository_code = ArclightRepositoryMapper.map_to_code(aspace_repository_code:,
                                                                      ead_id: resource['ead_id'])
      directory = "#{data_dir}/#{arclight_repository_code}"
      DownloadEadJob.perform_later(resource_uri: resource['uri'], file_name: resource['ead_id'], data_dir: directory,
                                   index:)
    end
  end
  private_class_method :enqueue

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
  def perform(resource_uri:, file_name:, data_dir:, index: false)
    ead_xml = AspaceClient.new.resource_description(resource_uri)

    # Takes a supplied file name like 'abc 123/ABC.XML' and turns it into: 'abc-123-abc.xml'
    xml_file_name = file_name.sub(/(\.xml)?$/i, '').parameterize.concat('.xml')
    file_path = File.join(data_dir, xml_file_name.to_s)

    File.open(file_path, 'wb') do |f|
      ead = Nokogiri::XML(ead_xml, &:noblanks)
      f.puts ead.to_xml(indent: 2)
    end

    IndexEadJob.perform_later(file_path:) if index
  end
end
