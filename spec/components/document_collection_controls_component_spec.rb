# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentCollectionControlsComponent, type: :component do
  subject(:component) { described_class.new(response:, search_state:, blacklight_config:, params:) }

  let(:response) do
    instance_double(Blacklight::Solr::Response, current_page: 5,
                                                limit_value: 10,
                                                rows: 10,
                                                size: 10,
                                                total_count: 1_000,
                                                total_pages: 100,
                                                offset_value: 0,
                                                entry_name: 'entries')
  end
  let(:search_state) { Blacklight::SearchState.new(params, blacklight_config, CatalogController.new) }
  let(:blacklight_config) { Blacklight::Configuration.new }
  let(:params) { ActionController::Parameters.new({ key: '-document', paginate: 'true' }) }

  before do
    allow_any_instance_of(Blacklight::Search::PerPageComponent).to receive(:render?).and_return(true) # rubocop:disable RSpec/AnyInstance

    with_request_url '/catalog?id=sc0097-xml_donald-e-knuth-papers&key=-document&paginate=true' do
      render_inline(component)
    end
  end

  it 'renders the component' do
    expect(page).to have_text 'Number of results to display per page'
    expect(page).to have_text '1 - 10 of 1,000 entries'
  end
end
