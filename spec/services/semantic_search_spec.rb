# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SemanticSearch do
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

  describe '.embedding_model' do
    around do |example|
      original = ENV.fetch('SEMANTIC_SEARCH_EMBEDDING_MODEL', nil)
      example.run
      original.nil? ? ENV.delete('SEMANTIC_SEARCH_EMBEDDING_MODEL') : ENV['SEMANTIC_SEARCH_EMBEDDING_MODEL'] = original
    end

    it 'defaults to the model the corpus is indexed with' do
      ENV.delete('SEMANTIC_SEARCH_EMBEDDING_MODEL')
      expect(described_class.embedding_model).to eq('text-multilingual-embedding-002')
    end

    it 'can be overridden by ENV' do
      ENV['SEMANTIC_SEARCH_EMBEDDING_MODEL'] = 'text-embedding-005'
      expect(described_class.embedding_model).to eq('text-embedding-005')
    end
  end
end
