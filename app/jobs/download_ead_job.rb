# frozen_string_literal: true

##
# Background job to download an EAD XML file from ArchiveSpace
class DownloadEadJob < ApplicationJob
  def perform(ead_id:, resource_uri:, repo_code:, data_dir: ENV.fetch('DATA_DIR', 'data'), index: false)
    client = AspaceClient.new
    ead_xml = client.resource_description(resource_uri)

    file_name = ead_id.sub(/(\.xml)?$/i, '.xml')
    directory = "#{data_dir}/#{repo_code}"

    file_path = File.join(directory, file_name.to_s)

    File.open(file_path, 'wb') do |f|
      ead = Nokogiri::XML(ead_xml, &:noblanks)
      f.puts ead.to_xml(indent: 2)
    end

    IndexEadJob.perform_later(file_path:, repo_code:) if index
  end
end
