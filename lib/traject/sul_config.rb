# frozen_string_literal: true

require 'arclight'
require_relative 'sul/normalized_id'

settings do
  provide 'component_traject_config', File.join(__dir__, 'sul_component_config.rb')
  provide 'solr_writer.http_timeout', 1200
  provide 'resource_uri', ENV.fetch('RESOURCE_URI', nil)
  provide 'id_normalizer', 'Sul::NormalizedId'
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

# Some finding aids in OAC have empty elements that are indexed as empty strings in Solr.
# We want to remove these. This is not an issue with finding aids produced by ArchivesSpace.
each_record do |_record, context|
  context.output_hash['creator_ssim']&.reject!(&:blank?)
end
