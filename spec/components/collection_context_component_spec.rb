# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CollectionContextComponent, type: :component do
  subject(:component) { described_class.new(presenter:, download_component: Arclight::DocumentDownloadComponent) }

  let(:presenter) { instance_double(Blacklight::DocumentPresenter, document:) }
  let(:document) { instance_double(SolrDocument, collection:) }
  let(:collection) do
    instance_double(SolrDocument, normalized_title: 'Collection Title',
                                  unitid: 'ARS123',
                                  collection_unitid: 'ARS123',
                                  total_component_count: '10',
                                  online_item_count: '4',
                                  last_indexed: Time.zone.parse('2025-04-07'),
                                  downloads: downloads,
                                  collection?: true)
  end
  let(:downloads) { instance_double(Arclight::DocumentDownloads, files: [file]) }
  let(:file) { instance_double(Arclight::DocumentDownloads::File, href: 'https://example.com/file.txt', size: 1234, type: 'pdf') }

  before do
    render_inline(component)
  end

  it 'renders a download link' do
    expect(page).to have_text('Download finding aid')
  end

  it 'renders the unitid' do
    expect(page).to have_text('ARS123')
  end

  it 'renders the title' do
    expect(page).to have_text('Collection Title')
  end

  it 'renders information about the collection' do
    expect(page).to have_text('Total components')
    expect(page).to have_text('Items available online')
    expect(page).to have_text('Last indexed')
  end
end
