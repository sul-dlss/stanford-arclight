# frozen_string_literal: true

require 'arclight'
require_relative 'sul/normalized_id'

settings do
  provide 'component_traject_config', File.join(__dir__, 'sul_component_config.rb')
  provide 'solr_writer.http_timeout', 1200
  provide 'aspace_config_set', ENV.fetch('ASPACE_CONFIG_SET', nil)
  provide 'id_normalizer', 'Sul::NormalizedId'
end

to_field 'sul_ark_id_ssi',
         extract_xpath('/ead/archdesc/did/unitid[@type="ark"]/extref', to_text: false) do |_record, accumulator|
  accumulator.map! do |node|
    node.attributes['href']&.text&.[](%r{ark:/\S+})
  end
end

to_field 'sul_ark_shoulder_ssi',
         extract_xpath('/ead/archdesc/did/unitid[@type="ark"]/extref', to_text: false) do |_record, accumulator|
  accumulator.map! do |node|
    node.attributes['href']&.text&.match(%r{ark:/\d*/([a-z]*\d).*}) { |m| m[1] }
  end
end

load_config_file(File.expand_path("#{Arclight::Engine.root}/lib/arclight/traject/ead2_config.rb"))

# Some finding aids in OAC have empty elements that are indexed as empty strings in Solr.
# We want to remove these. This is not an issue with finding aids produced by ArchivesSpace.
each_record do |_record, context|
  context.output_hash['creator_ssim']&.reject!(&:blank?)
  # Remove from 'unitid_ssm' -- these ARK-related values live in <unitid> elements in the EAD
  context.output_hash['unitid_ssm']&.reject! { |v| v == 'Archival Resource Key' }
  context.output_hash['unitid_ssm']&.reject! { |v| v == 'Previous Archival Resource Key' }
  # Store a hashed version of the id for blacklight dynamic sitemaps
  context.output_hash['hashed_id_ssi'] = [Digest::MD5.hexdigest(context.output_hash['id'].first)]
end
