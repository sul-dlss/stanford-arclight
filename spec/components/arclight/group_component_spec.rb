# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Arclight::GroupComponent, type: :component do
  subject(:component) { described_class.new(group:) }

  let(:collection_id) { 'ars0043' }
  let(:component_doc1) do
    SolrDocument.new(id: 'ars0043-01', level_ssm: ['series'], normalized_title_ssm: 'Series 1',
                     _root_: collection_id)
  end
  let(:component_doc2) do
    SolrDocument.new(id: 'ars0043-02', level_ssm: ['file'], normalized_title_ssm: 'File 2',
                     _root_: collection_id)
  end
  let(:collection_solr_doc) do
    SolrDocument.new(id: collection_id, level_ssm: ['collection'], normalized_title_ssm: 'ARS Collection',
                     _root_: collection_id)
  end

  let(:group) do
    instance_double(Blacklight::Solr::Response::Group,
                    key: collection_id,
                    docs: group_docs,
                    total: group_total)
  end

  # Case 3 defaults: only component docs, no collection doc in results
  let(:group_docs) { [component_doc1, component_doc2] }
  let(:group_total) { 2 }

  before do
    allow(component_doc1).to receive(:collection).and_return(collection_solr_doc)
    allow(component_doc2).to receive(:collection).and_return(collection_solr_doc)
    allow(collection_solr_doc).to receive(:collection).and_return(collection_solr_doc)
    allow(collection_solr_doc).to receive(:repository_config).and_return(nil)
    allow(collection_solr_doc).to receive(:collection?).and_return(true)
    allow(collection_solr_doc).to receive(:collection_name).and_return('ARS Collection')
  end

  describe '#collection_doc_in_results' do
    context 'when the collection document is not in the group docs' do
      it { expect(component.collection_doc_in_results).to be_nil }
    end

    context 'when the collection document is among the group docs' do
      let(:group_docs) { [collection_solr_doc, component_doc1] }

      it { expect(component.collection_doc_in_results).to eq(collection_solr_doc) }
    end
  end

  describe '#component_docs' do
    context 'when no collection doc is in results (Case 3)' do
      it 'returns all group docs unchanged' do
        expect(component.component_docs).to eq([component_doc1, component_doc2])
      end
    end

    context 'when the collection doc is in results alongside components (Case 1)' do
      let(:group_docs) { [collection_solr_doc, component_doc1, component_doc2] }

      it 'excludes the collection doc' do
        expect(component.component_docs).to eq([component_doc1, component_doc2])
      end
    end

    context 'when only the collection doc matched (Case 2)' do
      let(:group_docs) { [collection_solr_doc] }

      it 'returns an empty array' do
        expect(component.component_docs).to be_empty
      end
    end
  end

  describe '#component_count' do
    context 'when no collection doc is in results (Case 3)' do
      let(:group_total) { 5 }

      it 'equals the group total' do
        expect(component.component_count).to eq(5)
      end
    end

    context 'when the collection doc is in results (Cases 1 and 2)' do
      let(:group_docs) { [collection_solr_doc, component_doc1] }
      let(:group_total) { 14 }

      it 'decrements the total by one' do
        expect(component.component_count).to eq(13)
      end
    end
  end

  describe '#more_component_results?' do
    context 'when all component results fit in the displayed cards' do
      let(:group_docs) { [component_doc1, component_doc2] }
      let(:group_total) { 2 }

      it { expect(component.more_component_results?).to be false }
    end

    context 'when there are more component results than displayed' do
      let(:group_docs) { [collection_solr_doc, component_doc1, component_doc2] }
      let(:group_total) { 14 }

      it { expect(component.more_component_results?).to be true }
    end
  end
end
