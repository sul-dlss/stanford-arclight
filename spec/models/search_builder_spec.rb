# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SearchBuilder do
  subject(:search_builder) { described_class.new scope }

  let(:blacklight_config) { Blacklight::Configuration.new }
  let(:scope) { instance_double ApplicationController, blacklight_config:, action_name: nil }

  describe '#apply_group_sort_parameter' do
    subject(:solr_parameters) do
      search_builder.with(query).processed_parameters
    end

    context 'when the results are grouped' do
      context 'when there is no query and results are sorted by relevance' do
        let(:query) { { q: '', group: 'true', sort: 'relevance' } }

        it 'sets the group.sort solr parameter' do
          expect(solr_parameters['group.sort']).to eq('if(eq(sort_isi,0),0,div(1,field(sort_isi))) desc')
        end
      end

      context 'when there is no query and sort is not set (and defaults to relevance)' do
        let(:query) { { q: '', group: 'true' } }

        it 'sets the group.sort solr parameter' do
          expect(solr_parameters['group.sort']).to eq('if(eq(sort_isi,0),0,div(1,field(sort_isi))) desc')
        end
      end

      context 'when there is a query' do
        let(:query) { { q: 'a query', group: 'true' } }

        it 'does not set the group.sort solr parameter' do
          expect(solr_parameters['group.sort']).to be_nil
        end
      end
    end

    context 'when results are not grouped' do
      let(:query) { { q: '', sort: 'relevance' } }

      it 'does not set the group.sort solr parameter' do
        expect(solr_parameters['group.sort']).to be_nil
      end
    end
  end

  describe '#min_match_for_boolean' do
    subject(:solr_parameters) do
      search_builder.with(query).processed_parameters
    end

    context 'when query has a boolean operator' do
      let(:query) { { q: 'archives AND (recorded OR sound)' } }

      it 'sets min match to 1' do
        expect(solr_parameters[:mm]).to eq('1')
      end
    end

    context 'when query has no boolean operator' do
      let(:query) { { q: 'archives' } }

      it 'does not set min match' do
        expect(solr_parameters[:mm]).to be_nil
      end
    end
  end
end
