# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SemanticSearch do
  around do |example|
    original = ENV.to_h.slice('ENABLE_SEMANTIC_INDEXING', 'ENABLE_SEMANTIC_QUERY')
    ENV.delete('ENABLE_SEMANTIC_INDEXING')
    ENV.delete('ENABLE_SEMANTIC_QUERY')
    example.run
    ENV.delete('ENABLE_SEMANTIC_INDEXING')
    ENV.delete('ENABLE_SEMANTIC_QUERY')
    original.each { |k, v| ENV[k] = v }
  end

  describe '.solr_vector' do
    it 'rounds values to a Solr-safe (float32) precision, dropping noise digits' do
      rounded = described_class.solr_vector([0.0000020771296931343386, 0.18754829466342926, -0.1])
      expect(rounded[0]).to be_within(1e-9).of(0.0000021)
      expect(rounded[1]).to be_within(1e-9).of(0.1875483)
      expect(rounded[2]).to eq(-0.1)
      # no absurdly long numbers that Solr's JSON parser would reject
      expect(JSON.generate(rounded)).not_to match(/\d{10,}/)
    end
  end

  describe '.gemini_native?' do
    around do |example|
      original = ENV.fetch('SEMANTIC_SEARCH_EMBEDDING_MODEL', nil)
      example.run
      original.nil? ? ENV.delete('SEMANTIC_SEARCH_EMBEDDING_MODEL') : ENV['SEMANTIC_SEARCH_EMBEDDING_MODEL'] = original
    end

    it 'routes the default model through the native gemini pass-through' do
      ENV.delete('SEMANTIC_SEARCH_EMBEDDING_MODEL')
      expect(described_class.embedding_model).to eq('gemini-embedding-2')
      expect(described_class.gemini_native?).to be true
    end

    it 'routes the Vertex text-embedding models through the OpenAI-compatible endpoint' do
      %w[text-multilingual-embedding-002 text-embedding-005].each do |model|
        ENV['SEMANTIC_SEARCH_EMBEDDING_MODEL'] = model
        expect(described_class.gemini_native?).to be false
      end
    end
  end

  describe '.truthy?' do
    it 'treats real booleans and common ENV string forms correctly' do
      expect(described_class.truthy?(true)).to be true
      expect(described_class.truthy?('true')).to be true
      expect(described_class.truthy?('1')).to be true
      expect(described_class.truthy?('on')).to be true
      expect(described_class.truthy?(false)).to be false
      expect(described_class.truthy?(nil)).to be false
      expect(described_class.truthy?('false')).to be false
      expect(described_class.truthy?('0')).to be false
    end
  end

  describe '.indexing_enabled? / .query_enabled?' do
    it 'default to false when neither Settings nor ENV enable them' do
      allow(described_class).to receive(:setting).and_return(nil)
      expect(described_class.indexing_enabled?).to be false
      expect(described_class.query_enabled?).to be false
    end

    it 'reads the ENV var when Settings is unavailable (Traject context)' do
      allow(described_class).to receive(:setting).and_return(nil)
      ENV['ENABLE_SEMANTIC_INDEXING'] = 'true'
      expect(described_class.indexing_enabled?).to be true
      expect(described_class.query_enabled?).to be false
    end

    it 'prefers Settings when present (Rails context)' do
      allow(described_class).to receive(:setting).with('semantic_search.query_enabled').and_return(true)
      allow(described_class).to receive(:setting).with('semantic_search.indexing_enabled').and_return(false)
      expect(described_class.query_enabled?).to be true
      expect(described_class.indexing_enabled?).to be false
    end
  end

  describe '.rrf_combiner_enabled?' do
    around do |example|
      original = ENV.fetch('SEMANTIC_SEARCH_RRF_COMBINER', nil)
      ENV.delete('SEMANTIC_SEARCH_RRF_COMBINER')
      example.run
      original.nil? ? ENV.delete('SEMANTIC_SEARCH_RRF_COMBINER') : ENV['SEMANTIC_SEARCH_RRF_COMBINER'] = original
    end

    it 'defaults to false (native combiner needs Solr 9.11; keep off on 9.10)' do
      allow(described_class).to receive(:setting).and_return(nil)
      expect(described_class.rrf_combiner_enabled?).to be false
    end

    it 'can be enabled via ENV for a Solr 9.11+ environment' do
      allow(described_class).to receive(:setting).and_return(nil)
      ENV['SEMANTIC_SEARCH_RRF_COMBINER'] = 'true'
      expect(described_class.rrf_combiner_enabled?).to be true
    end
  end
end
