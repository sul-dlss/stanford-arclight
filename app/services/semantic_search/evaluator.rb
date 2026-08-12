# frozen_string_literal: true

module SemanticSearch
  # Runs a set of test queries through the REAL search pipeline (the app's
  # SearchBuilder + SemanticQuery processor, via Blacklight::SearchService) once
  # per mode - keyword, hybrid, semantic - and reports both a per-query rank and
  # aggregate IR metrics (NDCG@10, MAP, MRR, P@10). Because it drives the same
  # code path a real search uses, the eval reflects exactly what ships.
  #
  # Powers the stage-only SemanticEvalController so a non-developer can compare
  # modes on curated queries without the CLI, env vars, or an API key.
  #
  # A query spec is { query:, expects: } where `expects` is a list of expected
  # hits, each a Solr id (`id:ars0001`) or a title substring, with an optional
  # `:GRADE` (0-3) suffix - ungraded hits default to grade 1, so a set with no
  # grades is scored exactly as binary. NDCG uses the grades; MAP/MRR/P@10
  # threshold at grade > 0.
  #
  # Metrics are scored against the DECLARED judgment set: every judged target
  # counts, whether or not a run retrieved it, so the numbers are recall-sensitive
  # and a target missed beyond POOL_DEPTH costs the score. (This deliberately does
  # NOT pool the ideal down to what was retrieved - see #score_relevance for why
  # that inflated results.) Metrics are therefore lower bounds only in the sense
  # that a target ranked past POOL_DEPTH is indistinguishable from one that is
  # absent. Queries with no expects are excluded from metrics.
  class Evaluator
    MODES = %w[keyword hybrid semantic].freeze
    POOL_DEPTH = 50  # results fetched per search (metric + pooling depth)
    DISPLAY = 5      # results shown per mode in the UI
    METRIC_KEYS = %i[ndcg ap rr p10].freeze
    MAX_QUERIES = 50 # guardrail: this runs MODES.size searches per query

    # Aggregate scorecard: mean of each metric per mode, over the queries that
    # have a relevant set. @return [Hash] { count:, modes: { mode => {ndcg,...} } }
    def self.summary(rows, modes = MODES)
      scored = rows.select { |row| row[:relevant].to_i.positive? }
      return { count: 0, modes: {} } if scored.empty?

      { count: scored.size, modes: averaged_modes(scored, modes) }
    end

    def self.averaged_modes(scored, modes)
      modes.index_with do |mode|
        metrics = scored.filter_map { |row| row.dig(:modes, mode, :metrics) }
        next nil if metrics.empty?

        METRIC_KEYS.index_with { |key| metrics.sum { |m| m[key] } / metrics.size }
      end.compact
    end
    private_class_method :averaged_modes

    # @param tuning [Hash] optional per-run overrides for the SemanticQuery knobs
    #   (topK / reRankDocs / reRankWeight / min-similarity). Honored because the
    #   page is gated by SemanticSearch.tuning_enabled?; blank values are dropped
    #   so the ENV defaults apply.
    # @param group_by_collection [Boolean] when true, collapse each mode's results
    #   to one row per collection (the highest-ranked component, keyed by `_root_`)
    #   before scoring - the grouped catalog view. In this mode an `id:` target
    #   matches the COLLECTION, so `id:ms_3791` counts whenever any of that
    #   collection's components rank. Off = flat, exact-doc-id scoring.
    def initialize(config: CatalogController.blacklight_config, modes: MODES, tuning: {}, group_by_collection: false)
      @config = config
      @modes = modes
      @tuning = tuning.to_h.compact_blank
      @group = group_by_collection
    end

    # @return [Array<Hash>] one row per query with a per-mode breakdown + metrics
    def call(specs)
      Array(specs).first(MAX_QUERIES).map { |spec| evaluate(spec) }
    end

    private

    def evaluate(spec)
      modes = @modes.index_with { |mode| run_mode(spec, mode) }
      base = { query: spec[:query], expects: spec[:expects], distractors: spec[:distractors] || {},
               meta: spec[:meta], modes: modes }
      spec[:expected_nothing] ? score_out_of_scope(base) : score_relevance(base)
    end

    # Ranking cases: graded NDCG/MAP/MRR/P@10 against the DECLARED judgment set.
    #
    # The ideal ranking is built from every judged target, NOT from the targets a
    # run happened to retrieve. Deriving it from retrieved docs makes the metrics
    # blind to recall - a run that finds 2 of 46 judged targets and ranks those two
    # well scored NDCG 0.398 instead of ~0.05 - and the overstatement grew with
    # judgment depth, so judging a case more thoroughly improved its score instead
    # of making it stricter. It also silently excluded a query from .summary
    # whenever a run found nothing, dropping exactly the hardest queries from the
    # average. Unretrieved targets now count against the score, as they should.
    def score_relevance(base)
      ideal = declared_grades(base[:expects])
      base[:modes].each_value do |data|
        next data[:metrics] = nil if data[:error]

        data[:found_relevant] = data[:rel].count(&:positive?)
        data[:metrics] = metrics(data[:rel], ideal)
      end
      base.merge(expected_nothing: false, relevant: ideal.size)
    end

    # Grades of every judged target, best first - the true ideal ranking. Grade 0
    # entries are documented false matches, not targets, so they are excluded.
    #
    # NOTE: in group_by_collection mode, targets that are components of the SAME
    # collection collapse to one retrievable row, so a case judged at component
    # level can have an ideal larger than anything a grouped run could retrieve.
    # Judge at collection level when running grouped.
    def declared_grades(expects)
      Array(expects).map { |expect| split_grade(expect).last }.select(&:positive?).sort.reverse
    end

    # out_of_scope cases: success is returning nothing (the min-similarity floor
    # should suppress confident junk), so each mode passes iff it found nothing.
    def score_out_of_scope(base)
      base[:modes].each_value { |data| data[:passed] = data[:error] ? nil : data[:num_found].to_i.zero? }
      base.merge(expected_nothing: true, relevant: 0)
    end

    def run_mode(spec, mode)
      response = search(spec[:query], mode)
      docs = ranked_docs(response)
      rel = docs.map { |doc| grade_of(doc, spec[:expects]) } # 0 = not relevant, 1-3 = graded
      ids = docs.map { |doc| match_id(doc) } # collection ids when grouped, else doc ids
      { num_found: response.total, rank: rel.index(&:positive?)&.+(1), rel: rel,
        ids: ids, results: display_results(docs, ids, rel) }
    rescue StandardError => e
      { error: "#{e.class}: #{e.message}" }
    end

    # Ranked docs to score: as returned, or one row per collection (top-ranked
    # component wins) in group_by_collection mode.
    def ranked_docs(response)
      docs = response.documents
      @group ? docs.uniq { |doc| collection_of(doc) } : docs
    end

    def display_results(docs, ids, rel)
      docs.first(DISPLAY).each_with_index.map { |doc, i| { id: ids[i], title: title_of(doc), hit: rel[i].positive? } }
    end

    # Graded NDCG@10, plus MAP / MRR / P@10 (which threshold at grade > 0). `rel`
    # is the per-position grade list; `ideal` is the DECLARED grades sorted desc,
    # so ideal.size is the full judged count and AP divides by it.
    def metrics(rel, ideal)
      { ndcg: ndcg_at(rel, 10, ideal),
        ap: average_precision(rel, ideal.size),
        rr: (i = rel.index(&:positive?)) ? 1.0 / (i + 1) : 0.0,
        p10: rel.first(10).count(&:positive?) / 10.0 }
    end

    def ndcg_at(rel, cutoff, ideal)
      dcg = rel.first(cutoff).each_with_index.sum { |grade, i| grade.zero? ? 0.0 : grade / Math.log2(i + 2) }
      idcg = ideal.first(cutoff).each_with_index.sum { |grade, i| grade / Math.log2(i + 2) }
      idcg.zero? ? 0.0 : dcg / idcg
    end

    def average_precision(rel, total_relevant)
      return 0.0 if total_relevant.zero?

      found = 0.0
      rel.each_with_index.sum { |grade, i| grade.positive? ? (found += 1) / (i + 1) : 0.0 } / total_relevant
    end

    def search(query, mode)
      user_params = { q: query, search_field: mode, per_page: POOL_DEPTH }.merge(@tuning)
      service = Blacklight::SearchService.new(config: @config, user_params: user_params)
      result = service.search_results
      result.is_a?(Array) ? result.first : result
    end

    # The relevance grade (1-3) of a doc for these expects, or 0 if none match.
    # An expect is an `id:...` or a title substring, with an optional `:GRADE`
    # suffix (default 1, so an ungraded set stays binary). The suffix is a
    # PROVISIONAL syntax; the graded metric math below is the stable part, and
    # the parsing swaps out when the shared query-set format settles.
    def grade_of(doc, expects)
      Array(expects).filter_map do |expect|
        matcher, grade = split_grade(expect)
        grade if matches_one?(doc, matcher)
      end.max || 0
    end

    def split_grade(expect)
      m = /:([0-3])\z/.match(expect)
      m ? [expect[0...m.begin(0)], m[1].to_i] : [expect, 1]
    end

    def matches_one?(doc, matcher)
      if matcher.start_with?('id:')
        match_id(doc) == matcher.delete_prefix('id:')
      else
        title_of(doc).downcase.include?(matcher.downcase)
      end
    end

    # The id a target/pool are keyed on: collection id when grouped, else doc id.
    def match_id(doc)
      @group ? collection_of(doc) : doc_id(doc)
    end

    # A doc's parent collection: Solr's `_root_` when present, else the id up to
    # `_aspace_` (ArcLight component ids are `<collection>_aspace_...`, and a
    # collection-level record has no `_aspace_`, so it maps to itself).
    def collection_of(doc)
      Array(doc['_root_']).first.presence || doc_id(doc).to_s.split('_aspace_').first
    end

    def doc_id(doc)
      doc.respond_to?(:id) ? doc.id : doc['id']
    end

    def title_of(doc)
      Array(doc['normalized_title_ssm']).first.to_s.squish
    end
  end
end
