# frozen_string_literal: true

require 'arclight'

settings do
  provide 'component_traject_config', File.join(__dir__, 'sul_component_config.rb')
  provide 'solr_writer.http_timeout', 1200
  provide 'resource_uri', ENV.fetch('RESOURCE_URI', nil)
end

to_field 'ead_filename_ssi' do |_record, accumulator|
  accumulator << File.basename(settings['command_line.filename'])
end

to_field 'repository_uri_ssi' do |_record, accumulator|
  accumulator << settings['resource_uri'].to_s[%r{/repositories/\d*}]
end

to_field 'resource_uri_ssi' do |_record, accumulator|
  accumulator << settings['resource_uri']
end

load_config_file(File.expand_path("#{Arclight::Engine.root}/lib/arclight/traject/ead2_config.rb"))
