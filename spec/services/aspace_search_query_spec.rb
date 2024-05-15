# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AspaceSearchQuery, type: :service do
  let(:aspace_client) { instance_double('AspaceClient') }
  let(:aspace_search_query) { described_class.new(client: aspace_client, repository_id: '1', query: 'test') }

  describe '#query_params' do
    it 'returns query params using the q parameter' do
      expect(aspace_search_query.query_params).to eq({ q: 'test' })
    end
  end

  describe '#keys_to_return' do
    it 'uses uri as the key to return' do
      expect(aspace_search_query.keys_to_return).to eq(['uri'])
    end
  end
end
