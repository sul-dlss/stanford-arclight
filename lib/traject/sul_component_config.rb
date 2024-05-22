# frozen_string_literal: true

require 'arclight'
require_relative 'sul/normalized_title'

settings do
  provide 'component_traject_config', __FILE__
  provide 'title_normalizer', 'Sul::NormalizedTitle'
end

load_config_file(File.expand_path("#{Arclight::Engine.root}/lib/arclight/traject/ead2_component_config.rb"))

# Some finding aids in OAC have empty elements that are indexed as empty strings in Solr.
# We want to remove these. This is not an issue with finding aids produced by ArchivesSpace.
each_record do |_record, context|
  context.output_hash['creator_ssim']&.reject!(&:blank?)
end
