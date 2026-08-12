# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SemanticTuningComponent, type: :component do
  subject(:component) { described_class.new(search_state:) }

  let(:params) { ActionController::Parameters.new(q: 'ships', search_field: 'hybrid') }
  let(:search_state) { Blacklight::SearchState.new(params, CatalogController.blacklight_config) }

  before do
    allow(SemanticSearch).to receive_messages(query_enabled?: query_enabled, tuning_enabled?: tuning_enabled)
  end

  context 'when semantic query and tuning are both enabled' do
    let(:query_enabled) { true }
    let(:tuning_enabled) { true }

    before do
      with_controller_class(CatalogController) do
        with_request_url('/catalog?q=ships&search_field=hybrid') { render_inline(component) }
      end
    end

    it 'renders the tuning panel with all knobs and an apply button' do
      expect(page).to have_field('semantic_top_k')
      expect(page).to have_field('semantic_rerank_docs')
      expect(page).to have_field('semantic_rerank_weight')
      expect(page).to have_field('semantic_min_similarity')
      expect(page).to have_button('Apply')
    end

    it 'preserves the current query and search field as hidden fields' do
      expect(page).to have_css('input[type=hidden][name="q"][value="ships"]', visible: :all)
      expect(page).to have_css('input[type=hidden][name="search_field"][value="hybrid"]', visible: :all)
    end
  end

  context 'when tuning is disabled' do
    let(:query_enabled) { true }
    let(:tuning_enabled) { false }

    before { render_inline(component) }

    it 'renders nothing' do
      expect(page).to have_no_css('.semantic-tuning')
    end
  end

  context 'when semantic query is disabled' do
    let(:query_enabled) { false }
    let(:tuning_enabled) { true }

    before { render_inline(component) }

    it 'renders nothing' do
      expect(page).to have_no_css('.semantic-tuning')
    end
  end
end
