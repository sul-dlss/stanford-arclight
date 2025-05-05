# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CollectionContextComponent, type: :component do # rubocop:disable RSpec/MultipleMemoizedHelpers
  subject(:component) { described_class.new(presenter:, download_component: DocumentDownloadComponent) }

  let(:presenter) { instance_double(Blacklight::DocumentPresenter, document:) }
  let(:document) { instance_double(SolrDocument, collection:) }
  let(:repository_config) do
    instance_double(Arclight::Repository, request_config_present?: true,
                                          available_request_types: ['aeon_web_ead'],
                                          request_config_for_type: {})
  end
  let(:collection) do
    SolrDocument.new(id: 'ars123',
                     normalized_title_ssm: 'Collection Title',
                     unitid_ssm: 'ARS123',
                     level_ssm: ['collection'],
                     component_level_isim: [0],
                     timestamp: '2025-05-03T12:18:58.114Z')
  end
  let(:downloads) { instance_double(Arclight::DocumentDownloads, files: [file]) }
  let(:file) { instance_double(Arclight::DocumentDownloads::File, href: 'https://example.com/file.txt', size: 1234, type: 'pdf') }

  before do
    allow(collection).to receive_messages(repository_config:,
                                          downloads: downloads,
                                          requestable?: true,
                                          ead_file: 'ars123.xml',
                                          ead_file_without_namespace_href: 'https://example.com/ars123.xml')
    with_controller_class(CatalogController) do
      render_inline(component)
    end
  end

  it 'renders a download link' do
    expect(page).to have_text('Download finding aid')
  end

  it 'renders the unitid' do
    expect(page).to have_text('ARS123')
  end

  it 'renders the title as a link' do
    expect(page).to have_link(text: 'Collection Title', href: '/catalog/ars123')
  end

  it 'renders the request link' do
    expect(page).to have_text('Request')
  end

  it 'renders information about the collection' do
    expect(page).to have_text('Total components')
    expect(page).to have_text('Items available online')
    expect(page).to have_text('Last indexed')
  end
end
