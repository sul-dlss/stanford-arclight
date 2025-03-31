# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CollectionSourceComponent, type: :component do
  subject(:component) { described_class.new(document:) }

  let(:document) { SolrDocument.new(id: 'abc123', timestamp: '2024-05-17T14:56:22.751Z') }
  let(:aspace_settings) { Config::Options.new(default: Config::Options.new(url: 'https://aspace-stage.sample.edu')) }
  let(:display_setting) { true }

  before do
    allow(Settings).to receive_messages(aspace: aspace_settings, display_collection_source: display_setting)
    render_inline(component)
  end

  context 'when the display_collection_source is configured to display' do
    context 'when the finding aid is from OAC' do
      it 'renders the message' do
        expect(page).to have_text 'The data source for this collection is Online Archive of California. ' \
                                  'The collection was updated on May 17, 2024.'
        expect(page).to have_link 'Online Archive of California'
      end
    end

    context 'when the finding aid is from aspace stage' do
      let(:document) { SolrDocument.new(id: 'abc123', repository_uri_ssi: '/repositories/11') }

      it 'renders the message' do
        expect(page).to have_text 'The data source for this collection is ArchivesSpace stage. ' \
                                  'The collection is up to date.'
      end
    end

    context 'when the finding aid is from aspace prod' do
      let(:aspace_settings) { Config::Options.new(default: Config::Options.new(url: 'https://aspace-prod.sample.edu')) }
      let(:document) { SolrDocument.new(id: 'abc123', repository_uri_ssi: '/repositories/11') }

      it 'renders the message' do
        expect(page).to have_text 'The data source for this collection is ArchivesSpace. ' \
                                  'The collection is up to date.'
      end
    end
  end

  context 'when the display_collection_source is not configured to display' do
    let(:display_setting) { false }

    before { allow(Settings).to receive(:display_collection_source).and_return(false) }

    it 'renders nothing' do
      expect(page).to have_no_css('*')
    end
  end
end
