# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CollectionSummary::Check do
  subject(:problems) { described_class.new(evidence, summary).problems }

  let(:evidence) do
    CollectionSummary::Evidence.new(Nokogiri::XML(<<~XML))
      <ead><archdesc level="collection">
        <did><unittitle>Concert hall records</unittitle></did>
        #{access}
        <dsc>
          <c01 id="s10" level="series"><did><unittitle>Series 10: Recordings</unittitle></did>
            <c02 id="t1"><did><unittitle>Tapes, 1974</unittitle></did></c02>
            <c02 id="t2"><did><unittitle>Tapes, 1975</unittitle><physdesc>3,450.5 feet</physdesc></did></c02>
          </c01>
          <c01 id="d1" level="series"><did><unittitle>Donor files</unittitle></did>
            <accessrestrict><p>Closed for 50 years.</p></accessrestrict>
            <c02><did><unittitle>Smithers, Waylon: Restrictions waiver</unittitle></did></c02>
          </c01>
        </dsc>
      </archdesc></ead>
    XML
  end
  let(:access) { '' }
  let(:statements) do
    [{ 'text' => 'Series 10 holds 2 tapes of 20th-century music from 1974 and 1975.', 'cites' => [1] },
     { 'text' => 'The hall kept 3,450.5 feet of its own recordings.', 'cites' => [2, 3] },
     { 'text' => 'Donor files are closed.', 'cites' => [4] }]
  end
  let(:highlights) do
    [{ 'label' => 'Formats', 'value' => 'Tapes', 'cites' => [2] },
     { 'label' => 'Restrictions', 'value' => 'Donor files, closed for 50 years', 'cites' => [4] }]
  end
  let(:summary) { { 'statements' => statements, 'highlights' => highlights } }

  it 'accepts numbers from the facts, the cited lines, and years' do
    expect(problems).to eq []
  end

  context 'with citations that do not resolve' do
    let(:statements) do
      [{ 'text' => 'Uncited.', 'cites' => [] }, { 'text' => 'Out of range.', 'cites' => [9] },
       { 'text' => 'Has no ref.', 'cites' => [5] }]
    end

    it 'reports each one' do
      expect(problems).to eq ['no citation: Uncited.', 'unknown citation [9]', 'citation [5] has no ref to link']
    end
  end

  context 'with a number that the evidence does not hold' do
    let(:statements) { super().take(2) + [{ 'text' => 'It holds 600 boxes.', 'cites' => [1] }] }

    it { expect(problems).to eq ['number not in the facts or the cited lines: 600'] }
  end

  context 'with a name that appears only in a restricted part' do
    let(:statements) { super().take(2) + [{ 'text' => 'Donor files name Smithers.', 'cites' => [4] }] }

    it { expect(problems).to eq ['word from a restricted part: Smithers'] }
  end

  context 'with too many citations' do
    let(:statements) { super().take(2) + [{ 'text' => 'Donor files are closed.', 'cites' => [0, 1, 2, 3, 4] }] }

    it { expect(problems).to eq ['5 citations, expected 1..4'] }
  end

  context 'with a praise word' do
    let(:statements) { super().take(2) + [{ 'text' => 'Extensive donor files are closed.', 'cites' => [4] }] }

    it { expect(problems).to eq ['praise word: Extensive'] }
  end

  context 'when the summary says the collection is open but no note says so' do
    let(:statements) { super().take(2) + [{ 'text' => 'The collection is open for research.', 'cites' => [0] }] }

    it { expect(problems).to eq ['access not stated in the notes: The collection is open for research.'] }

    context 'with an access note' do
      let(:access) { '<accessrestrict><p>Open for research.</p></accessrestrict>' }

      it { expect(problems).to eq [] }
    end
  end

  context 'with too few entries and a new label' do
    let(:statements) { super().take(1) }
    let(:highlights) { [{ 'label' => 'Oddities', 'value' => 'Tapes', 'cites' => [2] }] }

    it 'reports the counts and the label' do
      expect(problems).to eq ['1 statements, expected 3..5', '1 highlights, expected 2..4', 'new label: Oddities']
    end
  end
end
