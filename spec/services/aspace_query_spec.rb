# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AspaceQuery, type: :service do
  let(:aspace_client) { instance_double(AspaceClient) }
  let(:options) do
    { published: true, suppressed: false, contains_fields: ['ead_id'], select_fields: %w[ead_id uri] }
  end
  let(:aspace_query) { described_class.new(client: aspace_client, repository_id: '1', options:) }

  describe '#query_params' do
    it 'returns query params using the aq parameter using valid JSON' do
      # rubocop:disable Layout/LineLength
      expect(aspace_query.query_params).to eq({ aq: '{' \
                                                    '"query":{"jsonmodel_type":"boolean_query","op":"AND","subqueries":[' \
                                                    '{"field":"publish","value":true,"jsonmodel_type":"field_query","negated":false,"literal":false},' \
                                                    '{"field":"primary_type","value":"resource","jsonmodel_type":"field_query","negated":false,"literal":false},' \
                                                    '{"field":"ead_id","value":"*","jsonmodel_type":"field_query","negated":false,"literal":false}' \
                                                    ']}' \
                                                    '}' })
      # rubocop:enable Layout/LineLength
    end
  end

  describe '#keys_to_return' do
    it 'uses the fields specified in the options as the keys to return' do
      expect(aspace_query.keys_to_return).to match_array(%w[ead_id uri])
    end
  end
end
