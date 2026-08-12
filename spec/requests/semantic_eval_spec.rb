# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Semantic eval page' do
  describe 'GET /semantic-eval' do
    context 'when the tuning flag is off (production default)' do
      before { allow(SemanticSearch).to receive_messages(tuning_enabled?: false, query_enabled?: true) }

      it 'is hidden (404)' do
        get semantic_eval_path
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when semantic query is off' do
      before { allow(SemanticSearch).to receive_messages(tuning_enabled?: true, query_enabled?: false) }

      it 'is hidden (404)' do
        get semantic_eval_path
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when both flags are on (stage/dev)' do
      before { allow(SemanticSearch).to receive_messages(tuning_enabled?: true, query_enabled?: true) }

      it 'renders the form (query set + ranking knobs) and does not run without input' do
        get semantic_eval_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Semantic search evaluation')
        expect(response.body).to include('Kirsten Flagstad') # from the default query set
        expect(response.body).to include('semantic_rerank_weight')  # a ranking knob input
        expect(response.body).not_to include('Results <span')       # results only after a run
      end

      it 'runs the evaluator with the submitted queries and tuning knobs' do
        hit = { title: 'Jazz Collection', hit: true }
        met = { ndcg: 0.9, ap: 0.8, rr: 1.0, p10: 0.2 }
        evaluator = instance_double(SemanticSearch::Evaluator, call: [
                                      { query: 'jazz', expects: ['jazz'], relevant: 1,
                                        modes: { 'keyword' => { num_found: 5, rank: 1, results: [hit], metrics: met },
                                                 'hybrid' => { num_found: 6, rank: 1, results: [hit], metrics: met },
                                                 'semantic' => { num_found: 100, rank: nil, metrics: met,
                                                                 results: [{ title: 'Other', hit: false }] } } }
                                    ])
        allow(SemanticSearch::Evaluator).to receive(:new)
          .with(tuning: hash_including(semantic_rerank_weight: '20'), group_by_collection: false).and_return(evaluator)

        get semantic_eval_path, params: { queries: 'jazz => jazz', semantic_rerank_weight: '20' }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Jazz Collection')
        expect(response.body).to include('rank 1')
        expect(response.body).to include('NDCG@10') # metrics scorecard rendered
      end

      it 'passes the group-by-collection toggle through and shows the grouped badge' do
        evaluator = instance_double(SemanticSearch::Evaluator, call: [])
        allow(SemanticSearch::Evaluator).to receive(:new)
          .with(tuning: anything, group_by_collection: true).and_return(evaluator)

        get semantic_eval_path, params: { queries: 'jazz => jazz', group: '1' }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('grouped by collection')
      end

      it 'runs a pasted JSON suite and renders the out-of-scope pass/fail section' do
        row = { query: 'zzz', expects: [], distractors: {}, meta: { test_type: 'out_of_scope' },
                expected_nothing: true, relevant: 0,
                modes: { 'keyword' => { num_found: 0, passed: true, results: [] },
                         'hybrid' => { num_found: 3, passed: false, results: [] },
                         'semantic' => { num_found: 5, passed: false, results: [] } } }
        allow(SemanticSearch::Evaluator).to receive(:new)
          .and_return(instance_double(SemanticSearch::Evaluator, call: [row]))

        json = '[{"query":"zzz","test_type":"out_of_scope","expected_nothing":true,"judgments":[]}]'
        post semantic_eval_path, params: { test_cases_json: json }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Out-of-scope checks')
        expect(response.body).to include('PASS — no results')
      end

      it 'shows a friendly error for malformed JSON instead of blowing up' do
        post semantic_eval_path, params: { test_cases_json: '[{"query": ' }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Couldn't run the suite")
      end
    end
  end
end
