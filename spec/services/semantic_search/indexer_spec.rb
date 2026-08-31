# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SemanticSearch::Indexer do
  let(:output_hash) do
    { 'id' => ['abc123'], 'normalized_title_ssm' => ['A Collection'] }
  end
  let(:embedding_service) { instance_double(SemanticSearch::EmbeddingService) }
  let(:logger) { instance_double(Logger, warn: nil, error: nil) }

  describe '.add_embedding!' do
    it 'writes the returned vector into embedding_vector' do
      allow(embedding_service).to receive(:embed).and_return([0.1, 0.2, 0.3])

      described_class.add_embedding!(output_hash, embedding_service:, logger:)

      expect(output_hash['embedding_vector']).to eq([0.1, 0.2, 0.3])
      expect(embedding_service).to have_received(:embed).with(
        kind_of(String), task_type: SemanticSearch::EmbeddingService::DOCUMENT_TASK_TYPE
      )
    end

    it 'stamps model / input-hash / schema-version / dimensions alongside the vector' do
      allow(embedding_service).to receive(:embed).and_return([0.1, 0.2, 0.3])

      described_class.add_embedding!(output_hash, embedding_service:, logger:)

      expect(output_hash).to include(
        'embedding_model_ssi' => [SemanticSearch.embedding_model],
        'embedding_schema_version_ssi' => [SemanticSearch::EMBED_SCHEMA_VERSION],
        'embedding_dimensions_is' => [3] # the stub vector's length
      )
      # matches the cache key (SHA256 of the embedded text)
      expect(output_hash['embedding_input_hash_ssm'].first).to match(/\A\h{64}\z/)
    end

    it 'skips documents with no embeddable text and makes no API call' do
      # `embed` is intentionally not stubbed: if it were called on this
      # verifying double it would raise, so a clean run proves no API call.
      doc = { 'id' => ['x'], 'level_ssim' => ['file'] }
      expect { described_class.add_embedding!(doc, embedding_service:, logger:) }.not_to raise_error
      expect(doc).not_to have_key('embedding_vector')
      expect(doc).not_to have_key('embedding_model_ssi') # no vector => no provenance stamp
    end

    context 'when the embedding API fails' do
      before do
        allow(embedding_service).to receive(:embed)
          .and_raise(SemanticSearch::EmbeddingService::ApiError, 'timeout')
      end

      it 'does not raise, leaves the doc without a vector, and logs' do
        expect do
          described_class.add_embedding!(output_hash, embedding_service:, logger:)
        end.not_to raise_error

        expect(output_hash).not_to have_key('embedding_vector')
        expect(logger).to have_received(:warn).with(/skipped embedding for abc123/)
      end
    end

    context 'when an unexpected error occurs' do
      before do
        allow(embedding_service).to receive(:embed).and_raise(StandardError, 'kaboom')
      end

      it 'still does not fail the indexing job for that doc' do
        expect do
          described_class.add_embedding!(output_hash, embedding_service:, logger:)
        end.not_to raise_error
        expect(output_hash).not_to have_key('embedding_vector')
        expect(logger).to have_received(:error).with(/unexpected embedding error/)
      end
    end

    context 'with an embedding cache' do
      let(:vector) { [0.1, 0.2, 0.3] }

      it 'uses a cached vector and never calls the API' do
        allow(embedding_service).to receive(:embed)
        cache = instance_double(SemanticSearch::EmbeddingCache::Sqlite, fetch: vector)

        described_class.add_embedding!(output_hash, embedding_service:, cache:, logger:)

        expect(output_hash['embedding_vector']).to eq(vector)
        expect(embedding_service).not_to have_received(:embed)
      end

      it 'embeds and stores on a miss in write mode' do
        allow(embedding_service).to receive(:embed).and_return(vector)
        cache = instance_double(SemanticSearch::EmbeddingCache::Sqlite, fetch: nil, writable?: true, store: nil)

        described_class.add_embedding!(output_hash, embedding_service:, cache:, logger:)

        expect(output_hash['embedding_vector']).to eq(vector)
        expect(cache).to have_received(:store).with(kind_of(String), vector)
      end

      it 'embeds but does not store on a miss in read-only mode' do
        allow(embedding_service).to receive(:embed).and_return(vector)
        # `store` intentionally not stubbed: a clean run proves it is not called.
        cache = instance_double(SemanticSearch::EmbeddingCache::Sqlite, fetch: nil, writable?: false)

        described_class.add_embedding!(output_hash, embedding_service:, cache:, logger:)

        expect(output_hash['embedding_vector']).to eq(vector)
      end
    end

    context 'when in generation mode' do
      let(:generator) { instance_double(SemanticSearch::CacheGenerator, add: nil) }

      before { allow(described_class).to receive_messages(generating?: true, generator:) }

      it 'buffers the text for batching and writes no Solr vector' do
        described_class.add_embedding!(output_hash, embedding_service:, logger:)

        expect(generator).to have_received(:add).with(kind_of(String))
        expect(output_hash).not_to have_key('embedding_vector')
      end
    end
  end
end
