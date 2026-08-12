# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SemanticSearch::Evaluator do
  describe '#call' do
    subject(:evaluator) { described_class.new(config: :cfg, modes: %w[keyword semantic]) }

    let(:responses) do
      {
        'keyword' => response_with([['d0', 'Random doc'], ['d1', 'Kirsten Flagstad Collection'], ['d2', 'Other']], 42),
        'semantic' => response_with([%W[z0 \u67D0\u4E2D\u6587\u6863\u6848], %w[z1 Unrelated]], 100)
      }
    end

    before do
      allow(Blacklight::SearchService).to receive(:new) do |user_params:, **|
        instance_double(Blacklight::SearchService, search_results: responses.fetch(user_params[:search_field]))
      end
    end

    it 'runs each mode and reports the rank of a matching title, with hit flags' do
      row = evaluator.call([{ query: 'opera sopranos', expects: ['Flagstad'] }]).first

      expect(row[:query]).to eq('opera sopranos')
      expect(row[:modes]['keyword'][:rank]).to eq(2)      # Flagstad title is 2nd
      expect(row[:modes]['keyword'][:num_found]).to eq(42)
      expect(row[:modes]['semantic'][:rank]).to be_nil    # not present
      expect(row[:modes]['semantic'][:results])
        .to eq([{ id: 'z0', title: '某中文档案', hit: false }, { id: 'z1', title: 'Unrelated', hit: false }])
    end

    it 'matches an expected Solr id anywhere in the results' do
      row = evaluator.call([{ query: 'q', expects: ['id:d1'] }]).first
      expect(row[:modes]['keyword'][:rank]).to eq(2)
      expect(row[:modes]['keyword'][:results][1]).to eq(id: 'd1', title: 'Kirsten Flagstad Collection', hit: true)
    end

    it 'leaves rank nil when no expects are given' do
      row = evaluator.call([{ query: 'anything', expects: [] }]).first
      expect(row[:modes]['keyword'][:rank]).to be_nil
    end

    it 'captures a per-mode error without aborting the run' do
      allow(Blacklight::SearchService).to receive(:new) do |**|
        instance_double(Blacklight::SearchService).tap do |s|
          allow(s).to receive(:search_results).and_raise(StandardError, 'solr down')
        end
      end

      row = evaluator.call([{ query: 'x', expects: ['y'] }]).first
      expect(row[:modes]['keyword'][:error]).to match(/solr down/)
    end

    it 'caps the number of queries run' do
      specs = Array.new(described_class::MAX_QUERIES + 5) { { query: 'q', expects: [] } }
      expect(evaluator.call(specs).size).to eq(described_class::MAX_QUERIES)
    end

    it 'threads non-blank tuning knobs into every search and drops blank ones' do
      captured = []
      allow(Blacklight::SearchService).to receive(:new) do |user_params:, **|
        captured << user_params
        instance_double(Blacklight::SearchService, search_results: response_with([], 0))
      end

      described_class.new(config: :cfg, modes: %w[hybrid],
                          tuning: { semantic_rerank_weight: '20', semantic_min_similarity: '' })
                     .call([{ query: 'q', expects: [] }])

      expect(captured.first).to include(semantic_rerank_weight: '20')
      expect(captured.first).not_to have_key(:semantic_min_similarity) # blank dropped => ENV default
    end

    it 'computes NDCG@10 / MAP / MRR / P@10 against the pooled relevant set' do
      allow(Blacklight::SearchService).to receive(:new) do |user_params:, **|
        docs = if user_params[:search_field] == 'keyword'
                 response_with([%w[d1 Target], %w[d2 A], %w[d3 B]], 3)   # target at rank 1
               else
                 response_with([%w[x1 A], %w[x2 B], %w[d1 Target]], 3)   # target at rank 3
               end
        instance_double(Blacklight::SearchService, search_results: docs)
      end

      row = described_class.new(config: :cfg, modes: %w[keyword semantic])
                           .call([{ query: 'q', expects: ['id:d1'] }]).first

      expect(row[:relevant]).to eq(1) # one declared target
      kw = row[:modes]['keyword'][:metrics]
      expect(kw).to include(rr: 1.0, ap: 1.0)
      expect(kw[:ndcg]).to be_within(1e-9).of(1.0)
      expect(kw[:p10]).to be_within(1e-9).of(0.1)
      se = row[:modes]['semantic'][:metrics]
      expect(se[:rr]).to be_within(1e-9).of(1.0 / 3)
      expect(se[:ndcg]).to be_within(1e-9).of(1.0 / Math.log2(4)) # 0.5, discounted for rank 3
    end

    # Regression: the ideal ranking must come from the DECLARED judgments, not from
    # whatever the run retrieved. Scoring against the retrieved set made a run that
    # found 1 of 4 targets look perfect, and made deeper judging raise the score.
    it 'counts judged targets the run never retrieved against the score' do
      allow(Blacklight::SearchService).to receive(:new) do |**|
        # Only d1 of the four judged targets is retrieved, and it is ranked first.
        instance_double(Blacklight::SearchService,
                        search_results: response_with([%w[d1 Target], %w[z1 Noise]], 2))
      end

      row = described_class.new(config: :cfg, modes: %w[keyword])
                           .call([{ query: 'q', expects: ['id:d1:3', 'id:d2:3', 'id:d3:3', 'id:d4:3'] }]).first

      expect(row[:relevant]).to eq(4) # all four judged targets, not just the one found
      metrics = row[:modes]['keyword'][:metrics]
      expect(row[:modes]['keyword'][:found_relevant]).to eq(1)
      # Ranking the single found target first is NOT a perfect score any more.
      expect(metrics[:ndcg]).to be < 0.5
      expect(metrics[:ap]).to be_within(1e-9).of(0.25) # 1 of 4 targets, at rank 1
      expect(metrics[:rr]).to be_within(1e-9).of(1.0)  # MRR is recall-insensitive by design
    end

    it 'in group_by_collection mode collapses components and matches an id against the collection' do
      allow(Blacklight::SearchService).to receive(:new) do |**|
        docs = response_with([%w[ms_1_aspace_a First], %w[ms_1_aspace_b Second], %w[ms_2_aspace_c Other]], 3)
        instance_double(Blacklight::SearchService, search_results: docs)
      end

      row = described_class.new(config: :cfg, modes: %w[keyword], group_by_collection: true)
                           .call([{ query: 'q', expects: ['id:ms_1'] }]).first

      kw = row[:modes]['keyword']
      expect(kw[:results].size).to eq(2)                        # ms_1's two components collapse to one row
      expect(kw[:results].first).to eq(id: 'ms_1', title: 'First', hit: true)
      expect(kw[:rank]).to eq(1)                                # collection ms_1 ranks first and matches
      expect(kw[:ids]).to eq(%w[ms_1 ms_2])                     # pooled on collection ids, keyed by _root_
      expect(row[:relevant]).to eq(1)                           # one relevant collection pooled
    end

    it 'in flat mode an exact collection id does NOT match a component doc id' do
      allow(Blacklight::SearchService).to receive(:new) do |**|
        docs = response_with([%w[ms_1_aspace_a First]], 1)
        instance_double(Blacklight::SearchService, search_results: docs)
      end

      row = described_class.new(config: :cfg, modes: %w[keyword])
                           .call([{ query: 'q', expects: ['id:ms_1'] }]).first
      expect(row[:modes]['keyword'][:rank]).to be_nil
    end

    it 'scores an out_of_scope case as pass/fail on returning nothing, with no metrics' do
      allow(Blacklight::SearchService).to receive(:new) do |user_params:, **|
        total = user_params[:search_field] == 'keyword' ? 0 : 12 # keyword finds nothing, semantic returns junk
        instance_double(Blacklight::SearchService, search_results: response_with([], total))
      end

      row = described_class.new(config: :cfg, modes: %w[keyword semantic])
                           .call([{ query: 'zzz', expects: [], expected_nothing: true }]).first

      expect(row[:expected_nothing]).to be(true)
      expect(row[:relevant]).to eq(0)
      expect(row[:modes]['keyword'][:passed]).to be(true)      # 0 results = pass
      expect(row[:modes]['semantic'][:passed]).to be(false)    # 12 results = fail
      expect(row[:modes]['keyword']).not_to have_key(:metrics) # no ranking metrics for out-of-scope
    end

    it 'carries the test-case metadata through onto the row' do
      meta = { test_type: 'conceptual_thematic', subject_id: 'peoples-temple' }
      row = evaluator.call([{ query: 'q', expects: [], meta: meta }]).first
      expect(row[:meta]).to eq(meta)
    end

    it 'uses relevance grades (:3) so ranking a lesser hit above a better one is penalized' do
      allow(Blacklight::SearchService).to receive(:new) do |user_params:, **|
        docs = if user_params[:search_field] == 'keyword'
                 response_with([%w[d1 Best], %w[d2 Ok]], 2)     # grade 3 then grade 1 (ideal order)
               else
                 response_with([%w[d2 Ok], %w[d1 Best]], 2)     # grade 1 above grade 3
               end
        instance_double(Blacklight::SearchService, search_results: docs)
      end

      row = described_class.new(config: :cfg, modes: %w[keyword semantic])
                           .call([{ query: 'q', expects: ['id:d1:3', 'id:d2:1'] }]).first

      expect(row[:relevant]).to eq(2)
      expect(row[:modes]['keyword'][:metrics][:ndcg]).to be_within(1e-9).of(1.0) # ideal order
      ideal = (3 / Math.log2(2)) + (1 / Math.log2(3))
      semantic = (1 / Math.log2(2)) + (3 / Math.log2(3))
      expect(row[:modes]['semantic'][:metrics][:ndcg]).to be_within(1e-9).of(semantic / ideal)
    end
  end

  describe '.summary' do
    it 'averages each metric per mode over queries that have a relevant set' do
      rows = [
        { relevant: 1, modes: { 'keyword' => { metrics: { ndcg: 1.0, ap: 1.0, rr: 1.0, p10: 0.1 } },
                                'hybrid' => { metrics: { ndcg: 0.5, ap: 0.4, rr: 0.5, p10: 0.1 } } } },
        { relevant: 0, modes: {} } # no ground truth -> excluded from the averages
      ]

      summary = described_class.summary(rows, %w[keyword hybrid])
      expect(summary[:count]).to eq(1)
      expect(summary[:modes]['keyword'][:ndcg]).to eq(1.0)
      expect(summary[:modes]['hybrid'][:rr]).to eq(0.5)
    end

    it 'reports zero scored queries when none have a relevant set' do
      expect(described_class.summary([{ relevant: 0, modes: {} }])).to eq(count: 0, modes: {})
    end
  end

  # entries: array of [id, title] pairs (or bare titles, id auto-assigned)
  def response_with(entries, total)
    docs = entries.each_with_index.map do |entry, i|
      id, title = entry.is_a?(Array) ? entry : ["doc#{i}", entry]
      { 'id' => id, 'normalized_title_ssm' => [title] }
    end
    instance_double(Blacklight::Solr::Response, documents: docs, total: total)
  end
end
