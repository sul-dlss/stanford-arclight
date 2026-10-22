# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AboutThisCollectionComponent, type: :component do
  let(:document) do
    SolrDocument.new(id:, repository_ssm: [repository], level_ssm: [level], component_level_isim: [0])
  end
  let(:id) { 'ars0043' }
  let(:repository) { 'Archive of Recorded Sound' }
  let(:level) { 'collection' }

  before do
    render_inline(described_class.new(document:))
  end

  it 'describes the series and the largest one' do
    expect(page).to have_text 'About this collection'
    expect(page).to have_text '657 components in 10 series'
    expect(page).to have_text 'The largest is Series 10: Concert Recordings, with 254 components'
    expect(page).to have_link 'Series 10: Concert Recordings', href: '/catalog/ars0043_aspace_ref52_k0v'
  end

  it 'shows the AI summary with numbered links to the cited components' do
    expect(page).to have_text 'Recordings of concerts at the hall make up the largest series.'
    expect(page).to have_css 'dt', text: 'Formats'
    expect(page).to have_link href: '/catalog/ars0043_aspace_ref52_k0v', exact_text: '1', count: 4
    expect(page).to have_text 'make up the largest series.1, 2'
    expect(page).to have_text 'may require 24 hours notice.1, 2'
    expect(page).to have_text '1 review note'
  end

  context 'when the collection is one flat list' do
    let(:id) { 'universite-de-toulouse' }
    let(:repository) { 'Cubberley Education Library' }

    it { expect(page).to have_text '6 components in a single list.' }
    it { expect(page).to have_no_text '(AI Version)' }
  end

  context 'when the collection has no components' do
    let(:id) { 'cubb1967' }
    let(:repository) { 'Cubberley Education Library' }

    it { expect(page).to have_text 'No contents list.' }
  end

  context 'when the EAD file is missing' do
    let(:id) { 'not-a-file' }

    it { expect(page).to have_no_text 'About this collection' }
  end

  context 'when the document is not a collection' do
    let(:level) { 'series' }

    it { expect(page).to have_no_text 'About this collection' }
  end
end
