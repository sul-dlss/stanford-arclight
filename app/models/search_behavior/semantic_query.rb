# frozen_string_literal: true

module SearchBehavior
  # SearchBuilder processor chain behavior for semantic (vector) search.
  #
  # The semantic modes are folded into the search field dropdown (see
  # CatalogController) rather than a separate control: two search fields,
  # `hybrid` and `semantic`, are offered when ENABLE_SEMANTIC_QUERY is on, and
  # `hybrid` is the default. This processor engages only for those two fields;
  # the ordinary lexical fields (keyword, name, title, ...) are left untouched.
  #
  #   * semantic - the KNN vector query replaces the lexical query.
  #   * hybrid   - the lexical edismax query and a KNN vector query are combined
  #     so documents the keywords missed but that are semantically relevant can
  #     still surface (recall). Two fusion strategies, chosen by
  #     SemanticSearch.rrf_combiner_enabled?:
  #       - default (bool.should + reRank): the two queries are `bool.should`
  #         clauses and the top docs are reranked by vector similarity via Solr's
  #         reRank parser. Works on Solr 9.10. Its weakness is that keyword's
  #         much larger raw-score scale can bury a strong semantic-only hit
  #         (raw-score fusion), so ranking is imperfect - but facets, counts, and
  #         pagination are all correct over the true result set.
  #       - RRF combiner (opt-in): Solr's native `combiner` fuses the two by RANK
  #         (Reciprocal Rank Fusion), which is scale-independent and fixes the
  #         burying. It needs Solr 9.11 / 10.1 (SOLR-17319) - on 9.10 it silently
  #         returns match-all - so it stays behind the flag until Solr is upgraded.
  #
  # Both are one Solr request, so facets, counts, and pagination are computed
  # over the blended result set - unlike an app-side merge. The nested edismax
  # subquery inherits qf/pf/mm/defType from the `search` request handler
  # defaults, so keyword ranking is unchanged from today.
  #
  # The including SearchBuilder must add :add_semantic_query to its processor
  # chain. No-op when the flag is off (default), for lexical search fields, or
  # when there is no keyword query. Any embedding failure is caught and the
  # request falls back to pure lexical search, so semantic search can never break
  # keyword search.
  module SemanticQuery
    # search_field values that trigger semantic search, mapped to query mode.
    SEMANTIC_SEARCH_FIELDS = { 'hybrid' => :hybrid, 'semantic' => :vector }.freeze

    # Default number of nearest neighbors pulled from the vector index, how many
    # top docs to rerank, and how strongly the vector score weighs in the
    # rerank. ENV-tunable defaults; can be overridden per request when the
    # tuning flag is on (see #top_k etc.).
    SEMANTIC_TOP_K = Integer(ENV.fetch('SEMANTIC_SEARCH_TOP_K', 100))
    SEMANTIC_RERANK_DOCS = Integer(ENV.fetch('SEMANTIC_SEARCH_RERANK_DOCS', 100))
    # Bumped 5 -> 10 (2026-08-21): the hybrid-marginal A/B showed reRankWeight was
    # under-tuned - 10-20 lifted retrieval across every query category (concepts,
    # vocab, cross-lingual) with known-item hits still protected, because keyword's
    # much larger BM25 scale keeps a strong keyword match on top regardless. See
    # docs/semantic_search_eval_plan.md.
    SEMANTIC_RERANK_WEIGHT = Float(ENV.fetch('SEMANTIC_SEARCH_RERANK_WEIGHT', 10))

    # Optional minimum cosine similarity for vector hits - the out-of-scope /
    # "no results" knob. When > 0 the vector clause becomes a `vectorSimilarity`
    # floor instead of a topK KNN, so hits below the cutoff are dropped: a
    # genuinely out-of-scope query returns few/no vector matches and hybrid
    # falls back to keyword (relevant keyword hits are untouched by the floor),
    # while a truly-empty query yields Blacklight's native "no results". Default
    # 0 = off; calibrate per-corpus on stage. Keep it below ~0.83 or it starts
    # cutting borderline in-scope hits like cross-lingual matches (which score
    # ~0.828 here); 0.80 is a safe starting point.
    SEMANTIC_MIN_SIMILARITY = Float(ENV.fetch('SEMANTIC_SEARCH_MIN_SIMILARITY', 0))

    # RRF fusion constant (k in 1/(k+rank)); 60 is the well-established default.
    # Used only by the dormant RRF combiner path (rrf_combiner_enabled?), which
    # can't run until Solr 9.11, so it is an ENV constant rather than a per-
    # request tuning knob.
    SEMANTIC_RRF_K = Integer(ENV.fetch('SEMANTIC_SEARCH_RRF_K', 60))

    # Upper bounds for per-request tuning overrides, kept near the useful range
    # (not just a safety cap): beyond these, values mostly add Solr latency/noise
    # without changing the top results. reRankWeight saturates well before 100
    # (cosine scores are 0-1), and topK/reRankDocs past ~1000 don't affect page 1.
    MAX_TOP_K = 1000
    MAX_RERANK_DOCS = 1000
    MAX_RERANK_WEIGHT = 100.0
    MAX_MIN_SIMILARITY = 1.0

    # URL params (honored only when SemanticSearch.tuning_enabled?); persist
    # across facet/pagination navigation.
    TUNING_PARAMS = %i[
      semantic_top_k semantic_rerank_docs semantic_rerank_weight semantic_min_similarity
    ].freeze

    def add_semantic_query(solr_parameters)
      return unless semantic_query_applicable?

      # Compute the vector BEFORE mutating solr_parameters: this is the only step
      # that can raise, so a failure leaves the pure lexical query intact.
      vector = SemanticSearch::QueryEmbeddingCache.new.embed(blacklight_params[:q])
      return if vector.blank?

      apply_semantic_query(solr_parameters, vector)
    rescue StandardError => e
      Rails.logger.warn("[SemanticSearch] semantic query skipped: #{e.class}: #{e.message}")
    end

    private

    def semantic_query_applicable?
      return false unless SemanticSearch.query_enabled?
      return false unless SEMANTIC_SEARCH_FIELDS.key?(semantic_search_field)

      query = blacklight_params[:q]
      query.present? && query != '*:*'
    end

    def apply_semantic_query(solr_parameters, vector)
      if SEMANTIC_SEARCH_FIELDS[semantic_search_field] == :vector
        apply_vector_query(solr_parameters, vector_query(vector))
      else
        apply_hybrid_query(solr_parameters, blacklight_params[:q], vector)
      end
    end

    # The effective search field: the explicit param, or the configured default
    # (so a param-less search still honors the hybrid default).
    def semantic_search_field
      blacklight_params[:search_field].presence || default_search_field_key
    end

    def default_search_field_key
      default = blacklight_config.default_search_field
      default.respond_to?(:key) ? default.key : default
    end

    # The vector-search clause. Default is a topK KNN; when a minimum-similarity
    # floor is configured it becomes a `vectorSimilarity` query (returns only
    # docs at/above the cosine cutoff), so out-of-scope queries yield few/no
    # vector hits. Both are lucene-parsed `{!...}` strings.
    def vector_query(vector)
      literal = "[#{SemanticSearch.solr_vector(vector).join(',')}]"
      floor = min_similarity
      return "{!vectorSimilarity f=embedding_vector minReturn=#{floor}}#{literal}" if floor.positive?

      "{!knn f=embedding_vector topK=#{top_k}}#{literal}"
    end

    # Effective tuning values: the ENV default, optionally overridden by a
    # clamped URL param when SemanticSearch.tuning_enabled? (dev/stage only).
    def top_k
      tuned_integer(:semantic_top_k, SEMANTIC_TOP_K, MAX_TOP_K)
    end

    def rerank_docs
      tuned_integer(:semantic_rerank_docs, SEMANTIC_RERANK_DOCS, MAX_RERANK_DOCS)
    end

    def rerank_weight
      tuned_float(:semantic_rerank_weight, SEMANTIC_RERANK_WEIGHT, MAX_RERANK_WEIGHT)
    end

    def min_similarity
      tuned_float(:semantic_min_similarity, SEMANTIC_MIN_SIMILARITY, MAX_MIN_SIMILARITY)
    end

    def tuned_integer(param, default, max)
      return default unless SemanticSearch.tuning_enabled?

      raw = blacklight_params[param]
      return default if raw.blank?

      Integer(raw, exception: false)&.clamp(1, max) || default
    end

    def tuned_float(param, default, max)
      return default unless SemanticSearch.tuning_enabled?

      raw = blacklight_params[param]
      return default if raw.blank?

      Float(raw, exception: false)&.clamp(0.0, max) || default
    end

    def apply_vector_query(solr_parameters, knn)
      solr_parameters[:json] ||= {}
      # Wrap the KNN string in a bool clause so Solr parses it with the `lucene`
      # parser (which honors the `{!knn}` local param). A bare top-level query
      # string is instead parsed by the `search` handler's edismax defType,
      # which tokenizes the 768-number vector literal into thousands of terms
      # and trips Solr's maxClauseCount limit. (Hybrid mode is already a bool
      # object, so its nested KNN string is lucene-parsed and needs no wrap.)
      solr_parameters[:json][:query] = { bool: { must: [knn] } }
      # The KNN query is the whole query now; drop the plain lexical q.
      solr_parameters.delete(:q)
    end

    def apply_hybrid_query(solr_parameters, query, vector)
      if SemanticSearch.rrf_combiner_enabled?
        apply_combiner_hybrid(solr_parameters, query, vector)
      else
        apply_rerank_hybrid(solr_parameters, query, vector_query(vector))
      end
    end

    # Default hybrid fusion (Solr 9.10-compatible): the lexical edismax and KNN
    # queries are `bool.should` clauses (recall), then the top reRankDocs are
    # rescored by vector similarity (precision). Raw-score fusion, so a strong
    # semantic-only hit can still be outweighed by keyword's larger score scale;
    # the RRF combiner below fixes that once Solr supports it.
    def apply_rerank_hybrid(solr_parameters, query, knn)
      solr_parameters[:json] ||= {}
      solr_parameters[:json][:query] = {
        bool: { should: [{ edismax: { query: query } }, knn] }
      }
      solr_parameters[:rq] =
        "{!rerank reRankQuery=$knn_rq reRankDocs=#{rerank_docs} reRankWeight=#{rerank_weight}}"
      solr_parameters[:knn_rq] = knn
      # The lexical query is now carried by json.query; drop the plain q so Solr
      # does not also run it as a separate top-level query.
      solr_parameters.delete(:q)
    end

    # Rank-based hybrid fusion via Solr's native RRF `combiner` (SOLR-17319).
    # DORMANT until Solr 9.11 / 10.1 - on 9.10 the combiner params are ignored
    # and the query degrades to match-all, so this only runs behind
    # SemanticSearch.rrf_combiner_enabled?. The KNN leg must be a parser-wrapped
    # object (not a raw `{!knn}` string) for the combiner to accept it. (The
    # min-similarity floor is not applied here yet; wire it in when this path
    # goes live on Solr 9.11.)
    def apply_combiner_hybrid(solr_parameters, query, vector)
      solr_parameters[:json] ||= {}
      solr_parameters[:json][:queries] = {
        lexical: { edismax: { query: query } },
        semantic: { knn: { f: 'embedding_vector', topK: top_k, vector: SemanticSearch.solr_vector(vector) } }
      }
      solr_parameters['combiner'] = true
      solr_parameters['combiner.algorithm'] = 'rrf'
      solr_parameters['combiner.query'] = %w[lexical semantic]
      solr_parameters['combiner.rrf.k'] = SEMANTIC_RRF_K
      # The lexical query is carried by json.queries now; drop the plain q.
      solr_parameters.delete(:q)
    end
  end
end
