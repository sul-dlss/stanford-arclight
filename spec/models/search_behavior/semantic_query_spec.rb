# frozen_string_literal: true

require 'rails_helper'

# Exercised through the real SearchBuilder host, which mixes the module in and
# registers :add_semantic_query in its processor chain. The semantic modes are
# folded into the search field dropdown (search_field = hybrid | semantic).
RSpec.describe SearchBehavior::SemanticQuery do
  subject(:builder) { SearchBuilder.new(CatalogController.new).with(params) }

  let(:params) { { q: 'ships', search_field: 'hybrid' } }
  let(:embedder) { instance_double(SemanticSearch::QueryEmbeddingCache, embed: [0.1, 0.2, 0.3]) }
  let(:knn) { '{!knn f=embedding_vector topK=100}[0.1,0.2,0.3]' }

  before { allow(SemanticSearch::QueryEmbeddingCache).to receive(:new).and_return(embedder) }

  describe '#add_semantic_query' do
    context 'when ENABLE_SEMANTIC_QUERY is off (default)' do
      before { allow(SemanticSearch).to receive(:query_enabled?).and_return(false) }

      it 'leaves the Solr query untouched even for the hybrid field, and never embeds' do
        solr_params = { q: 'ships' }
        builder.add_semantic_query(solr_params)
        expect(solr_params).to eq(q: 'ships')
        expect(SemanticSearch::QueryEmbeddingCache).not_to have_received(:new)
      end
    end

    context 'when ENABLE_SEMANTIC_QUERY is on' do
      before { allow(SemanticSearch).to receive(:query_enabled?).and_return(true) }

      context 'with the hybrid search field (default: bool.should + reRank)' do
        let(:solr_params) { { q: 'ships' } }

        before { builder.add_semantic_query(solr_params) }

        it 'combines the lexical edismax and KNN queries as bool.should clauses' do
          should = solr_params.dig(:json, :query, :bool, :should)
          expect(should.first).to eq(edismax: { query: 'ships' })
          expect(should.last).to eq(knn)
        end

        it 'reranks the top results by vector similarity and drops the plain q' do
          expect(solr_params[:rq]).to include('reRankQuery=$knn_rq', 'reRankDocs=100', 'reRankWeight=10')
          expect(solr_params[:knn_rq]).to eq(knn)
          expect(solr_params).not_to have_key(:q)
        end

        it 'does not emit combiner params (dormant until Solr 9.11)' do
          expect(solr_params).not_to have_key('combiner')
          expect(solr_params.dig(:json, :queries)).to be_nil
        end
      end

      context 'with the hybrid search field and the RRF combiner enabled (Solr 9.11+)' do
        let(:solr_params) { { q: 'ships' } }

        before do
          allow(SemanticSearch).to receive(:rrf_combiner_enabled?).and_return(true)
          builder.add_semantic_query(solr_params)
        end

        it 'runs the lexical edismax and a parser-wrapped KNN as two named subqueries' do
          queries = solr_params.dig(:json, :queries)
          expect(queries[:lexical]).to eq(edismax: { query: 'ships' })
          expect(queries[:semantic]).to eq(knn: { f: 'embedding_vector', topK: 100, vector: [0.1, 0.2, 0.3] })
        end

        it 'fuses them with the native RRF combiner and drops q and the reRank' do
          expect(solr_params['combiner']).to be(true)
          expect(solr_params['combiner.algorithm']).to eq('rrf')
          expect(solr_params['combiner.query']).to eq(%w[lexical semantic])
          expect(solr_params['combiner.rrf.k']).to eq(60)
          expect(solr_params).not_to have_key(:q)
          expect(solr_params).not_to have_key(:rq)
        end
      end

      context 'with the semantic search field' do
        let(:params) { { q: 'ships', search_field: 'semantic' } }
        let(:solr_params) { { q: 'ships' } }

        before { builder.add_semantic_query(solr_params) }

        it 'replaces the lexical query with the KNN query and does not rerank' do
          # Wrapped in a bool clause so Solr lucene-parses the {!knn} string
          # rather than tokenizing the vector under the handler's edismax.
          expect(solr_params.dig(:json, :query)).to eq(bool: { must: [knn] })
          expect(solr_params).not_to have_key(:q)
          expect(solr_params).not_to have_key(:rq)
        end
      end

      context 'with a lexical search field (keyword)' do
        let(:params) { { q: 'ships', search_field: 'keyword' } }

        it 'is a no-op and never embeds' do
          solr_params = { q: 'ships' }
          builder.add_semantic_query(solr_params)
          expect(solr_params).to eq(q: 'ships')
          expect(SemanticSearch::QueryEmbeddingCache).not_to have_received(:new)
        end
      end

      context 'with a scoped lexical search field (title)' do
        let(:params) { { q: 'ships', search_field: 'title' } }

        it 'is a no-op' do
          solr_params = { q: 'ships' }
          builder.add_semantic_query(solr_params)
          expect(solr_params).to eq(q: 'ships')
        end
      end

      context 'with tuning params but SEMANTIC_SEARCH_TUNING off (default)' do
        let(:params) do
          { q: 'ships', search_field: 'hybrid',
            semantic_top_k: '250', semantic_rerank_docs: '40', semantic_rerank_weight: '20.5' }
        end
        let(:solr_params) { { q: 'ships' } }

        before { builder.add_semantic_query(solr_params) }

        it 'ignores the params and uses the ENV defaults' do
          expect(solr_params.dig(:json, :query, :bool, :should).last)
            .to eq('{!knn f=embedding_vector topK=100}[0.1,0.2,0.3]')
          expect(solr_params[:rq]).to include('reRankDocs=100', 'reRankWeight=10')
        end
      end

      context 'with in-range tuning overrides and SEMANTIC_SEARCH_TUNING on' do
        let(:params) do
          { q: 'ships', search_field: 'hybrid',
            semantic_top_k: '250', semantic_rerank_docs: '40', semantic_rerank_weight: '20.5' }
        end
        let(:solr_params) { { q: 'ships' } }

        before do
          allow(SemanticSearch).to receive(:tuning_enabled?).and_return(true)
          builder.add_semantic_query(solr_params)
        end

        it 'applies the overridden topK, reRankDocs and reRankWeight' do
          expect(solr_params.dig(:json, :query, :bool, :should).last)
            .to eq('{!knn f=embedding_vector topK=250}[0.1,0.2,0.3]')
          expect(solr_params[:rq]).to include('reRankDocs=40', 'reRankWeight=20.5')
        end
      end

      context 'with an out-of-range tuning value and SEMANTIC_SEARCH_TUNING on' do
        let(:params) { { q: 'ships', search_field: 'hybrid', semantic_top_k: '999999' } }
        let(:solr_params) { { q: 'ships' } }

        before do
          allow(SemanticSearch).to receive(:tuning_enabled?).and_return(true)
          builder.add_semantic_query(solr_params)
        end

        it 'clamps to the maximum' do
          expect(solr_params.dig(:json, :query, :bool, :should).last).to include('topK=1000')
        end
      end

      context 'with a non-numeric tuning value and SEMANTIC_SEARCH_TUNING on' do
        let(:params) { { q: 'ships', search_field: 'hybrid', semantic_rerank_weight: 'lots' } }
        let(:solr_params) { { q: 'ships' } }

        before do
          allow(SemanticSearch).to receive(:tuning_enabled?).and_return(true)
          builder.add_semantic_query(solr_params)
        end

        it 'falls back to the default' do
          expect(solr_params[:rq]).to include('reRankWeight=10')
        end
      end

      context 'with a min-similarity floor in hybrid (SEMANTIC_SEARCH_TUNING on)' do
        let(:params) { { q: 'ships', search_field: 'hybrid', semantic_min_similarity: '0.85' } }
        let(:solr_params) { { q: 'ships' } }

        before do
          allow(SemanticSearch).to receive(:tuning_enabled?).and_return(true)
          builder.add_semantic_query(solr_params)
        end

        it 'swaps the topK KNN for a vectorSimilarity floor in both the should clause and reRank' do
          clause = solr_params.dig(:json, :query, :bool, :should).last
          expect(clause).to eq('{!vectorSimilarity f=embedding_vector minReturn=0.85}[0.1,0.2,0.3]')
          expect(solr_params[:knn_rq]).to eq(clause)
        end
      end

      context 'with a min-similarity floor in the semantic (vector-only) field' do
        let(:params) { { q: 'ships', search_field: 'semantic', semantic_min_similarity: '0.9' } }
        let(:solr_params) { { q: 'ships' } }

        before do
          allow(SemanticSearch).to receive(:tuning_enabled?).and_return(true)
          builder.add_semantic_query(solr_params)
        end

        it 'uses the vectorSimilarity floor as the whole query' do
          expect(solr_params.dig(:json, :query))
            .to eq(bool: { must: ['{!vectorSimilarity f=embedding_vector minReturn=0.9}[0.1,0.2,0.3]'] })
        end
      end

      context 'with no search field, when hybrid is the configured default' do
        let(:params) { { q: 'ships' } }

        before do
          allow(builder.blacklight_config)
            .to receive(:default_search_field).and_return(double(key: 'hybrid'))
        end

        it 'applies the hybrid query' do
          solr_params = { q: 'ships' }
          builder.add_semantic_query(solr_params)
          expect(solr_params.dig(:json, :query, :bool, :should)).to be_present
          expect(solr_params[:rq]).to be_present
        end
      end

      context 'when there is no keyword query' do
        let(:params) { { q: '', search_field: 'hybrid' } }

        it 'is a no-op' do
          solr_params = {}
          builder.add_semantic_query(solr_params)
          expect(solr_params).to be_empty
          expect(SemanticSearch::QueryEmbeddingCache).not_to have_received(:new)
        end
      end

      context 'when embedding fails' do
        before { allow(embedder).to receive(:embed).and_raise(StandardError, 'gemini down') }

        it 'falls back to pure lexical search (query unchanged) and logs' do
          allow(Rails.logger).to receive(:warn)
          solr_params = { q: 'ships' }
          builder.add_semantic_query(solr_params)
          expect(solr_params).to eq(q: 'ships')
          expect(Rails.logger).to have_received(:warn).with(/semantic query skipped/)
        end
      end
    end
  end
end
