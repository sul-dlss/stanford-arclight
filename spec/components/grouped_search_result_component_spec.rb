# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GroupedSearchResultComponent, type: :component do
  subject(:component) { described_class.new(document:) }

  let(:document) do
    SolrDocument.new(
      id: 'ars0043-01',
      level_ssm: ['file'],
      normalized_title_ssm: 'Jazz recordings, 1965-1970',
      containers_ssim: ['Box 3', 'Folder 12'],
      _root_: 'ars0043'
    )
  end

  before do
    with_controller_class(CatalogController) { render_inline(component) }
  end

  it 'renders a title link for the document' do
    expect(page).to have_link('Jazz recordings, 1965-1970')
  end

  it 'renders the container information' do
    expect(page).to have_text('Box 3, Folder 12')
  end

  it 'uses the compact result row class' do
    expect(page).to have_css('.al-grouped-result-row')
  end

  it 'renders an icon' do
    expect(page).to have_css('.al-grouped-result-icon')
  end

  context 'when the document has no containers' do
    let(:document) do
      SolrDocument.new(
        id: 'ars0043-02',
        level_ssm: ['series'],
        normalized_title_ssm: 'Series I: Early recordings',
        _root_: 'ars0043'
      )
    end

    before do
      with_controller_class(CatalogController) { render_inline(component) }
    end

    it 'does not render container span' do
      expect(page).to have_no_css('.al-grouped-result-containers')
    end
  end
end
