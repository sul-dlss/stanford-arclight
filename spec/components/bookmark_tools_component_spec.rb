# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BookmarkToolsComponent, type: :component do
  subject(:component) { described_class.new(response:, params:) }

  let(:response) do
    instance_double(
      Blacklight::Solr::Response,
      documents: %w[document1 document2 document3],
      total: 10,
      current_page: 1
    )
  end

  let(:params) { ActionController::Parameters.new({}) }

  before do
    with_request_url '/bookmarks.csv' do
      render_inline(component)
    end
  end

  it 'renders the bookmark tools' do
    expect(page).to have_link(text: 'Export to CSV', href: '/bookmarks.csv')
    expect(page).to have_text('Saved bookmarks are not permanent.')
    expect(page).to have_text('Exporting them will only include the current page')
  end

  context 'when all the bookmarks are shown' do
    let(:response) do
      instance_double(
        Blacklight::Solr::Response,
        documents: %w[document1 document2 document3],
        total: 3,
        current_page: 1
      )
    end

    it 'does not show the export info alert' do
      expect(page).to have_no_text('Exporting them will only include the current page')
    end
  end
end
