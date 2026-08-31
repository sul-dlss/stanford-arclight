# frozen_string_literal: true

require 'arclight'
require_relative 'sul/normalized_title'
require_relative 'sul/access_source'

settings do
  provide 'component_traject_config', __FILE__
  provide 'title_normalizer', 'Sul::NormalizedTitle'
end

to_field 'sul_ark_id_ssi',
         extract_xpath('./did/unitid[@type="ark"]/extref', to_text: false) do |_record, accumulator|
  accumulator.map! do |node|
    node.attributes['href']&.text&.[](%r{ark:/\S+})
  end
end

load_config_file(File.expand_path("#{Arclight::Engine.root}/lib/arclight/traject/ead2_component_config.rb"))

# Some finding aids in OAC have empty elements that are indexed as empty strings in Solr.
# We want to remove these. This is not an issue with finding aids produced by ArchivesSpace.
each_record do |_record, context|
  access_sources = {
    'parent_access_restrict_source' => Sul::AccessSource.nearest_ancestor(
      context, field: 'accessrestrict_html_tesm'
    )
  }
  if Array(context.output_hash['userestrict_html_tesm']).empty?
    access_sources['parent_access_terms_source'] = Sul::AccessSource.nearest_ancestor(
      context, field: 'userestrict_html_tesm'
    )
  end

  access_sources.compact.each do |prefix, source|
    source.to_h.each do |field, value|
      context.output_hash["#{prefix}_#{field}_ssi"] = [value]
    end
  end

  context.output_hash['creator_ssim']&.reject!(&:blank?)
  # Remove whitespace before trailing periods but keep the period. Common issue with ASpace-produced EAD.
  context.output_hash['language_ssim']&.map! { |value| value.gsub(/\s+\.\s*$/, '.').strip }
  # Remove from 'unitid_ssm' -- these ARK-related values live in <unitid> elements in the EAD
  context.output_hash['unitid_ssm']&.reject! { |v| v == 'Archival Resource Key' }
  context.output_hash['unitid_ssm']&.reject! { |v| v == 'Previous Archival Resource Key' }
  # Remove from 'unitid_ssm' -- ASpace archival object URIs
  context.output_hash['unitid_ssm']&.reject! { |v| v.match?(%r{^/repositories/\d+/archival_objects/\d+$}) }
  # Store a hashed version of the id for blacklight dynamic sitemaps
  context.output_hash['hashed_id_ssi'] = [Digest::MD5.hexdigest(context.output_hash['id'].first)]
end
