# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CollectionSummary::Organization do
  subject(:organization) { described_class.new(Nokogiri::XML("<ead><archdesc><dsc>#{dsc}</dsc></archdesc></ead>")) }

  context 'with series that hold nested components' do
    let(:dsc) do
      <<~XML
        <c01 id="ref.1" level="series"><did><unittitle>Correspondence</unittitle></did>
          <c02 level="subseries"><did><unittitle>1940s</unittitle></did>
            <c03 level="file"/><c03 level="file"/>
          </c02>
        </c01>
        <c01 level="series"><did><unittitle>Photographs</unittitle></did><c02 level="file"/></c01>
        <c01 level="file"><did><unittitle>Loose item</unittitle></did></c01>
      XML
    end

    it 'counts every component at every depth' do
      expect(organization.component_count).to eq 7
    end

    it 'treats only top-level components with children as groups' do
      expect(organization.groups.map(&:title)).to eq %w[Correspondence Photographs]
    end

    it 'finds the group with the most components beneath it' do
      expect(organization.largest_group.to_h).to eq(title: 'Correspondence', level: 'series',
                                                    component_count: 3, ref: 'ref-1')
    end

    it { expect(organization.arrangement).to eq :grouped }
  end

  context 'with unnumbered components' do
    let(:dsc) { '<c level="series"><did><unittitle>Records</unittitle></did><c level="file"/></c>' }

    it 'counts them like numbered components' do
      expect(organization.component_count).to eq 2
    end
  end

  context 'with one flat list' do
    let(:dsc) { '<c01 level="file"/><c01 level="file"/>' }

    it { expect(organization.arrangement).to eq :flat }
  end

  context 'with no components' do
    let(:dsc) { '' }

    it { expect(organization.arrangement).to eq :none }
  end
end
