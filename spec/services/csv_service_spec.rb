# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CsvService do
  include ActiveSupport::Testing::TimeHelpers

  describe '.response_to_csv' do
    let(:response) do
      instance_double(
        Blacklight::Solr::Response,
        documents: [
          instance_double(
            SolrDocument,
            id: '1',
            collection_unitid: 'collection_1',
            eadid: 'ead_1',
            level: 'level_1',
            normalized_title: 'Title 1',
            normalized_date: 'Date 1',
            containers: ['Container 1', 'Container 2'],
            abstract_or_scope: 'Description 1',
            extent: ['Extent 1']
          )
        ]
      )
    end

    it 'generates a CSV string from the response' do
      expect(described_class.response_to_csv(response: response)).to eq(
        "id,collection_id,ead_id,level,title,date,containers,description,extent\n" \
        "1,collection_1,ead_1,level_1,Title 1,Date 1,Container 1|Container 2,Description 1,Extent 1\n"
      )
    end
  end

  describe '.filename' do
    before do
      travel_to Time.zone.parse('2024-04-12T10:00:00.000+00:00')
    end

    it 'returns a filename with the current date' do
      expect(described_class.filename).to eq('response-20240412.csv')
    end

    it 'returns a filename with a custom prefix' do
      expect(described_class.filename(prefix: 'custom')).to eq('custom-20240412.csv')
    end
  end
end
