# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SemanticSearch::QueryEmbeddingCache do
  subject(:cache_wrapper) { described_class.new(embedding_service:, cache:) }

  let(:embedding_service) { instance_double(SemanticSearch::EmbeddingService) }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(embedding_service).to receive(:embed).and_return([0.5, 0.5]) }

  it 'embeds the query once and serves repeats from cache' do
    expect(cache_wrapper.embed('Old Maps')).to eq([0.5, 0.5])
    expect(cache_wrapper.embed('Old Maps')).to eq([0.5, 0.5])
    expect(embedding_service).to have_received(:embed).once
  end

  it 'normalizes the key so case/whitespace variants share a cache entry' do
    cache_wrapper.embed('Old   Maps')
    cache_wrapper.embed('old maps')
    expect(embedding_service).to have_received(:embed).once
  end

  it 'uses the query task type' do
    cache_wrapper.embed('ships')
    expect(embedding_service).to have_received(:embed)
      .with('ships', task_type: SemanticSearch::EmbeddingService::QUERY_TASK_TYPE)
  end
end
