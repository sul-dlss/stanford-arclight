# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/traject/sul/access_source')

RSpec.describe Sul::AccessSource do
  it 'adds the source record to indexed ancestor access information' do
    previous_repository = ENV.fetch('REPOSITORY_ID', nil)
    ENV['REPOSITORY_ID'] = 'uarc'

    indexer = Traject::Indexer::NokogiriIndexer.new
    indexer.load_config_file(Rails.root.join('lib/traject/sul_config.rb'))
    xml = Nokogiri::XML(Rails.root.join('spec/fixtures/traject/mcp_access_source.xml').read)
    xml.remove_namespaces!
    collection = indexer.map_record(xml)
    series = collection.fetch('components').first
    folder = series.fetch('components').first

    expect(series).to include(
      'parent_access_restrict_source_id_ssi' => ['access-test'],
      'parent_access_restrict_source_title_ssi' => ['Example records'],
      'parent_access_restrict_source_level_ssi' => ['collection']
    )
    expect(series).not_to include('parent_access_terms_source_id_ssi')
    expect(folder).to include(
      'parent_access_restrict_source_id_ssi' => ['access-test_series-1'],
      'parent_access_restrict_source_title_ssi' => ['Series 1'],
      'parent_access_restrict_source_level_ssi' => ['Series'],
      'parent_access_terms_source_id_ssi' => ['access-test_series-1'],
      'parent_access_terms_source_title_ssi' => ['Series 1'],
      'parent_access_terms_source_level_ssi' => ['Series']
    )
  ensure
    ENV['REPOSITORY_ID'] = previous_repository
  end
end
