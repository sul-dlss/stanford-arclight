# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsingTheseMaterialsComponent, type: :component do
  subject(:component) { described_class.new(document:) }

  let(:document) { SolrDocument.new(id: 'abc123', repository_ssm: ['Archive of Recorded Sound']) }

  before do
    render_inline(component)
  end

  it 'renders the links' do
    expect(page).to have_text 'Using these materials'
    expect(page).to have_link 'Info for visitors', href: 'https://library.stanford.edu/libraries/archive-recorded-sound'
    expect(page).to have_link 'How to request', href: 'https://library.stanford.edu/access-rare-and-distinctive-materials'
    expect(page).to have_link 'Access and use', href: '#access-and-use'
  end
end
