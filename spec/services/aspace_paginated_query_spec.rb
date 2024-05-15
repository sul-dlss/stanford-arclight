# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AspacePaginatedQuery do
  let(:aspace_client) { instance_double('AspaceClient') }
  let(:mocked_query_class) do
    Class.new do
      include AspacePaginatedQuery

      attr_reader :client, :repository_id, :query

      def initialize(client:, repository_id:, query:)
        @client = client
        @repository_id = repository_id
        @query = query
      end
    end
  end
  let(:mocked_query) { mocked_query_class.new(client: aspace_client, repository_id: '1', query: 'test') }

  describe '#each' do
    context 'when there is a single page of results' do
      before do
        allow(aspace_client).to receive(:authenticated_post).and_return(
          { 'last_page' => 1, 'results' => [{ 'uri' => '/repositories/1/resources/1' }] }.to_json
        )
      end

      it 'yields the only page' do
        expect { |block| mocked_query.each(&block) }.to yield_with_args(
          { 'uri' => '/repositories/1/resources/1' }
        )
      end
    end

    context 'when there are multiple pages of results' do
      before do
        allow(aspace_client).to receive(:authenticated_post).and_return(
          { 'last_page' => 2, 'results' => [{ 'uri' => '/repositories/1/resources/1' }] }.to_json,
          { 'last_page' => 2, 'results' => [{ 'uri' => '/repositories/1/resources/2' }] }.to_json
        )
      end

      it 'yields each page' do
        expect { |block| mocked_query.each(&block) }.to yield_successive_args(
          { 'uri' => '/repositories/1/resources/1' },
          { 'uri' => '/repositories/1/resources/2' }
        )
      end
    end
  end

  describe '#query_params' do
    it 'returns query params that can be safely merged with the pagination params' do
      expect { {}.merge(mocked_query.query_params) }.not_to raise_error
      expect(mocked_query.query_params).not_to have_key('page')
    end
  end

  describe '#keys_to_return' do
    it 'returns an array of keys to fetch from the query results' do
      expect(mocked_query.keys_to_return).to be_an(Array).and all(be_a(String))
      expect(mocked_query.keys_to_return).not_to be_empty
    end
  end
end
