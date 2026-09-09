# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SemanticSearch::SimilarDocuments do
  let(:connection) { instance_double(RSolr::Client) }

  # A doc as Solr returns it: `_root_` is a bare string, not an array.
  def solr_doc(id, root: nil, title: nil, collection_title: nil, score: nil)
    { 'id' => id, '_root_' => root || id, 'title_tesim' => title ? [title] : nil,
      'collection_title_tesim' => collection_title ? [collection_title] : nil,
      'repository_ssim' => ['University Archives'], 'score' => score }.compact
  end

  def response(docs)
    { 'response' => { 'docs' => docs } }
  end

  before do
    repository = instance_double(Blacklight::Solr::Repository, connection:)
    allow(Blacklight).to receive(:default_index).and_return(repository)
  end

  # Two GETs are issued with different `fl`: the vector fetch, then the
  # collection-resolution fetch. Stub them by that discriminator.
  def stub_get(field_list, docs)
    allow(connection).to receive(:get)
      .with('select', hash_including(params: hash_including(fl: field_list)))
      .and_return(response(docs))
  end

  def stub_solr(vector: Array.new(768, 0.1), knn: [], collections: [])
    stub_get(described_class::SOURCE_FIELDS, [{ 'id' => 'src', 'embedding_vector' => vector }.compact])
    stub_get(described_class::META_FIELDS, collections)
    allow(connection).to receive(:post).and_return(response(knn))
  end

  describe '.for' do
    it 'returns nearest collections, excluding the source collection and its components' do
      stub_solr(knn: [solr_doc('src', score: 1.0),                          # self - dropped
                      solr_doc('src_aspace_x1', root: 'src', score: 0.99),  # own component - dropped
                      solr_doc('other', title: 'Other collection', score: 0.9)],
                collections: [solr_doc('other', collection_title: 'Other collection')])

      results = described_class.for(SolrDocument.new(id: 'src', _root_: 'src'))

      expect(results.map(&:id)).to eq(['other'])
      # The collection itself was the nearest hit, so there is no component to
      # explain or link - the "matched on" line must not render.
      expect(results.first['matched_title']).to be_nil
      expect(results.first['matched_id']).to be_nil
    end

    it 'collapses multiple component hits from one collection into a single suggestion, ' \
       'and reports which document matched' do
      stub_solr(knn: [solr_doc('coll_aspace_a', root: 'coll', title: 'The interesting bit', score: 0.94),
                      solr_doc('coll_aspace_b', root: 'coll', title: 'Less interesting', score: 0.80)],
                collections: [solr_doc('coll', collection_title: 'Blandly Titled Records')])

      results = described_class.for(SolrDocument.new(id: 'src', _root_: 'src'))

      expect(results.size).to eq(1)
      expect(results.first.id).to eq('coll')
      # The collection is what we link to, but the component explains the match -
      # and is itself linkable, so its id has to survive the collection lookup.
      expect(results.first['matched_title']).to eq('The interesting bit')
      expect(results.first['matched_id']).to eq('coll_aspace_a')
      expect(results.first['score']).to eq(0.94)
    end

    it 'returns [] when the collection has no stored vector' do
      stub_solr(vector: nil)

      expect(described_class.for(SolrDocument.new(id: 'src', _root_: 'src'))).to eq([])
    end

    it 'returns [] and logs rather than raising when Solr errors' do
      # The rescue is StandardError-wide on purpose: a suggestion panel must never
      # take down a record page, whatever Solr or the network does.
      allow(connection).to receive(:get).and_raise(Faraday::ConnectionFailed, 'connection refused')
      allow(Rails.logger).to receive(:warn)

      expect(described_class.for(SolrDocument.new(id: 'src', _root_: 'src'))).to eq([])
      expect(Rails.logger).to have_received(:warn).with(/similar documents failed/)
    end

    it 'keys off the parent collection when given a component document' do
      stub_solr(knn: [solr_doc('other', title: 'Other', score: 0.9)],
                collections: [solr_doc('other', collection_title: 'Other')])

      described_class.for(SolrDocument.new(id: 'coll_aspace_deep', _root_: 'coll'))

      # The vector fetched is the COLLECTION's, never the thin component's.
      expect(connection).to have_received(:get)
        .with('select', hash_including(params: hash_including(q: 'id:"coll"')))
    end
  end
end
