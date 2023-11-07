# frozen_string_literal: true

require 'English'

# Queue up an indexing job
class DownloadEadJob
  include Sidekiq::Job

  def perform(ead_id, resource_uri, repo_code, index=false)
    client = AspaceClient.new
    ead_xml = client.resource_description(resource_uri)

    file_name = ead_id.sub(/(\.xml)?$/i, '.xml')
    directory = "#{ENV.fetch('DIR', 'data')}/#{repo_code}"

    file_path = File.join(directory, file_name.to_s)


    File.open(file_path, 'wb') do |f|
      # format the XML
      ead = Nokogiri::XML(ead_xml, &:noblanks)
      f.puts ead.to_xml(indent: 2)
    end

    IndexEadJob.perform_async(file_path, repo_code) if index
  end
end
