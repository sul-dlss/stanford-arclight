# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsingTheseMaterialsComponent, type: :component do
  subject(:component) { described_class.new(document:) }

  let(:document) do
    SolrDocument.new(id: 'abc123',
                     repository_ssm: ['Archive of Recorded Sound'],
                     accessrestrict_html_tesm: ["Collection is open for research. The full text version of the email contained in this collection is available in the Field Reading Room; a redacted version, displaying correspondents and extracted entities (personal and corporate names and locations) from Knuths email have been published in Stanford's online discovery module: http://epadd.stanford.edu/epadd/collections. 515 messages have been entirely restricted from both the discovery module and the full text version available in the reading room according to federal and state guidelines, and Stanford Libraries policy, for up to 80 years. These messages may contain financial, medical, legal, and other sensitive information. They will be made available in 2099."], # rubocop:disable Layout/LineLength
                     accessrestrict_tesim: ["Collection is open for research. The full text version of the email contained in this collection is available in the Field Reading Room; a redacted version, displaying correspondents and extracted entities (personal and corporate names and locations) from Knuths email have been published in Stanford's online discovery module: http://epadd.stanford.edu/epadd/collections. 515 messages have been entirely restricted from both the discovery module and the full text version available in the reading room according to federal and state guidelines, and Stanford Libraries policy, for up to 80 years. These messages may contain financial, medical, legal, and other sensitive information. They will be made available in 2099."], # rubocop:disable Layout/LineLength
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

  it 'truncates the restrictions text if longer than 250 characters' do
    # This text is past the 250 char mark
    expect(page).to have_no_text 'These messages may contain financial, medical, legal'
    expect(page).to have_link '[...]', href: '#access-and-use'
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
end
