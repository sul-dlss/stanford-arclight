# frozen_string_literal: true

##
# Background job to download an EAD XML file from ArchiveSpace
class DownloadEadJob < ApplicationJob
  # @example DownloadEadJob.perform_later(resource_uri: '/repositories/2/resources/5363',
  #                                       file_name: 'ars0018')
  # @param resource_uri [String] the URI of the resource in ArchivesSpace, such as '/repositories/2/resources/5363'
  # @param file_name [String] the name of the file to be created, such as 'ead1234'
  # @param data_dir [String] the path where the file should be saved, such as '/opt/app/arclight/data'
  #        the directory specified must already exist
  # @param index [Boolean] if true an IndexEadJob will be queued up with the stored file
  def perform(resource_uri:, file_name:, data_dir:, index: false)
    client = AspaceClient.new

    ead_xml = client.resource_description(resource_uri)

    xml_file_name = file_name.sub(/(\.xml)?$/i, '.xml')
    file_path = File.join(data_dir, xml_file_name.to_s)

    File.open(file_path, 'wb') do |f|
      ead = Nokogiri::XML(ead_xml, &:noblanks)
      f.puts ead.to_xml(indent: 2)
    end

    IndexEadJob.perform_later(file_path:) if index
  end
end
