# frozen_string_literal: true

require 'arclight'
require_relative 'sul/normalized_title'

settings do
  provide 'component_traject_config', __FILE__
  provide 'title_normalizer', 'Sul::NormalizedTitle'
end

load_config_file(File.expand_path("#{Arclight::Engine.root}/lib/arclight/traject/ead2_component_config.rb"))
