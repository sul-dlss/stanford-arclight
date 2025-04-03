# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CollectionUnitidPillComponent, type: :component do
  subject(:component) { described_class.new(document:) }

  let(:document) do
    SolrDocument.new(id: 'abc123',
                     level_ssm: ['collection'],
                     component_level_isim: [0],
                     unitid_ssm: ['SC12345'])
  end

  before do
    render_inline(component)
  end

  it 'renders the unit id' do
    expect(page).to have_text 'SC12345'
  end

  context 'when the document is not a collection' do
    let(:document) do
      SolrDocument.new(id: 'abc123',
                       level_ssm: ['item'],
                       component_level_isim: [10],
                       unitid_ssm: ['SC12345'])
    end

    it 'does not render the unit id' do
      expect(page).to have_no_text 'SC12345'
    end
  end
end
