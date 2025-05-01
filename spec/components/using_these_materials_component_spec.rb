# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsingTheseMaterialsComponent, type: :component do
  subject(:component) { described_class.new(document:) }

  let(:document) do
    SolrDocument.new(id: 'abc123',
                     repository_ssm: ['Archive of Recorded Sound'],
                     accessrestrict_html_tesm: ['Collection is open for research.'],
                     level_ssm: ['collection'],
                     component_level_isim: [0])
  end

  before do
    render_inline(component)
  end

  it 'renders the links' do
    expect(page).to have_text 'Using these materials'
    expect(page).to have_link 'Info for visitors', href: 'https://library.stanford.edu/libraries/archive-recorded-sound'
    expect(page).to have_link 'How to request', href: 'https://library.stanford.edu/access-rare-and-distinctive-materials'
    expect(page).to have_link 'Access and use', href: '#access-and-use'
    expect(page).to have_text 'Restrictions'
    expect(page).to have_text 'Collection is open for research.'
  end

  context 'when the document has no restrictions' do
    let(:document) do
      SolrDocument.new(id: 'abc123',
                       repository_ssm: ['Archive of Recorded Sound'],
                       accessrestrict_html_tesm: [''],
                       level_ssm: ['collection'],
                       component_level_isim: [0])
    end

    it 'does not render the restrictions' do
      expect(page).to have_no_text 'Restrictions'
    end
  end

  context 'when the document is not a collection' do
    let(:document) do
      SolrDocument.new(id: 'abc123',
                       repository_ssm: ['Archive of Recorded Sound'],
                       accessrestrict_html_tesm: ['Collection is open for research.'],
                       level_ssm: ['item'],
                       component_level_isim: [1])
    end

    it 'does not render the component' do
      expect(page).to have_no_text 'Using these materials'
    end
  end
end
