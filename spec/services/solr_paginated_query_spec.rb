# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SolrPaginatedQuery do
  subject(:solr_query) { described_class.new(filter_queries:, fields_to_return:) }

  let(:filter_queries) { { 'id' => 'ars-0043' } }
  let(:fields_to_return) { %w[id title_ssm] }

  describe '#all' do
    it 'returns all documents matching the filter queries and the fields specified' do
      expect(solr_query.all).to eq([['ars-0043', ['Ambassador Auditorium Collection']]])
    end
  end
end
