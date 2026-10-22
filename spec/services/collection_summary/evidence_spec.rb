# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CollectionSummary::Evidence do
  subject(:evidence) { described_class.new(Nokogiri::XML(xml)) }

  let(:xml) do
    <<~XML
      <ead><archdesc level="collection">
        <did><unittitle>Ginsberg papers</unittitle><unitdate>1937-1994</unitdate></did>
        <accessrestrict><head>Access</head><p>Open for research.</p></accessrestrict>
        <controlaccess><persname>Kerouac, Jack</persname></controlaccess>
        <dsc>
          <c01 id="ref.1" level="series"><did><unittitle>Correspondence</unittitle></did>
            <scopecontent><head>Scope</head><p>Letters from poets.</p></scopecontent><odd><head>Note</head></odd>
            <c02 id="ref2"><did><unittitle>Burroughs, William</unittitle><unitdate>1953</unitdate><dao/></did></c02>
          </c01>
          <c01><did><unittitle>Loose item</unittitle></did></c01>
          <c01 level="series"><did><unittitle>Medical files</unittitle></did>
            <accessrestrict><p>Closed until 2050.</p></accessrestrict>
            <c02><did><unittitle>Doe, Jane; Kerouac, Jack</unittitle></did></c02>
          </c01>
        </dsc>
      </archdesc></ead>
    XML
  end

  it 'gives the collection notes without their headings' do
    expect(evidence.text).to include('Access: Open for research.', 'Index (persname): Kerouac, Jack')
  end

  it 'numbers every component in document order, with its notes' do
    expect(evidence.text).to include(
      "[1] Correspondence | (series)\n    scope: Letters from poets.\n  " \
      "[2] Burroughs, William | 1953 | digital object\n[3] Loose item"
    )
  end

  it 'maps each number back to the ref Arclight indexes' do
    expect([evidence.ref(1), evidence.ref(2), evidence.ref(3), evidence.ref(4)]).to eq ['ref-1', 'ref2', nil, nil]
  end

  it 'gives the title for each number' do
    expect(evidence.title(2)).to eq 'Burroughs, William'
  end

  it 'has no ref for numbers below 1' do
    expect(evidence.ref(0)).to be_nil
  end

  it 'counts all components and the components beneath each top-level one' do
    expect(evidence.facts).to eq [5, 3, 1, 0, 1]
  end

  it 'marks restricted components and the components inside them' do
    expect(evidence.text).to include('[4] Medical files | (series) | restricted',
                                     '[5] Doe, Jane; Kerouac, Jack | restricted')
  end

  it 'keeps the words that appear only inside restricted components' do
    expect(evidence.private_words).to match_array %w[Doe Jane]
  end
end
