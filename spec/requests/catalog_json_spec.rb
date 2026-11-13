# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Catalog search JSON' do
  let(:query) { { q: 'Ambassador Auditorium', search_field: 'keyword' } }

  context 'when the search is grouped by collection' do
    before { get '/catalog.json', params: query.merge(group: true) }

    let(:collection) { response.parsed_body['data'].find { |item| item['id'] == 'ars0043' } }

    it 'returns each collection with its matching records as parts' do
      expect(response).to have_http_status(:ok)
      expect(collection).to include(
        'type' => 'collection',
        'attributes' => include('title' => include('Ambassador Auditorium Collection')),
        'links' => { 'self' => 'http://www.example.com/catalog/ars0043' }
      )
      expect(collection['parts']).to be_present
      expect(collection['parts']).to all(
        include('id' => start_with('ars0043_'), 'attributes' => include('breadcrumbs'), 'links' => include('self'))
      )
      expect(collection['parts'].pluck('id')).not_to include('ars0043')
      expect(collection['match_count']).to be >= collection['parts'].length
    end

    it 'counts the same matches as a search inside the collection' do
      match_count = collection['match_count']
      name = Blacklight.default_index.find('ars0043').documents.first['collection_ssim'].first

      get '/catalog.json', params: query.merge(f: { collection: [name] })

      expect(match_count).to eq response.parsed_body.dig('meta', 'pages', 'total_count')
    end

    it 'counts groups, not records, in the pagination' do
      expect(response.parsed_body.dig('meta', 'pages', 'total_count')).to eq response.parsed_body['data'].length
    end
  end

  context 'when the search is not grouped' do
    before { get '/catalog.json', params: query }

    it 'returns a flat list of records without parts' do
      data = response.parsed_body['data']

      expect(data).to be_present
      expect(data).to all(satisfy { |item| item.keys == %w[id type attributes links] })
    end
  end
end
