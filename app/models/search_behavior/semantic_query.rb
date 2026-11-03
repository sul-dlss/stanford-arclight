# frozen_string_literal: true

module SearchBehavior
  # SearchBuilder processor chain behavior for semantic (vector) search.
  #
  module SemanticQuery
    # search_field values that trigger semantic search, mapped to query mode.
    SEMANTIC_SEARCH_FIELDS = { 'hybrid' => :hybrid, 'semantic' => :vector }.freeze

    # Sentinel queries that mean "browse everything" rather than a real search
    # term. Embedding these would produce a meaningless vector, so semantic
    # ranking is skipped and the caller gets an unranked browse instead.
    # '*:*' is the convention used elsewhere in this app (e.g. FindingAidsController);
    # '*' is the MCP search tool's browse-all convention.
    BROWSE_ALL_QUERIES = ['*', '*:*'].freeze

    def add_semantic_query(solr_parameters)
      return unless semantic_query_applicable?

      vector = SemanticSearch::QueryEmbeddingCache.new.embed(blacklight_params[:q])
      return if vector.blank?

      apply_semantic_query(solr_parameters, vector)
    rescue StandardError => e
      Rails.logger.warn("[SemanticSearch] semantic query skipped: #{e.class}: #{e.message}")
    end

    private

    def semantic_query_applicable?
      return false unless SEMANTIC_SEARCH_FIELDS.key?(semantic_search_field)

      query = blacklight_params[:q]
      query.present? && BROWSE_ALL_QUERIES.exclude?(query)
    end

    def apply_semantic_query(solr_parameters, vector)
      if SEMANTIC_SEARCH_FIELDS[semantic_search_field] == :vector
        apply_vector_query(solr_parameters, knn_match_clause(vector))
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

    def vector_literal(vector)
      "[#{SemanticSearch.solr_vector(vector).join(',')}]"
    end

    def min_similarity_floor?
      Settings.semantic_search.min_similarity.positive?
    end

    def knn_query(vector)
      "{!knn f=embedding_vector topK=#{Settings.semantic_search.top_k}}#{vector_literal(vector)}"
    end

    # Unbounded: `minReturn` scores the whole collection, and how many docs
    # clear the cutoff varies wildly by query. Only safe combined with a
    # bounded clause (knn_match_clause) or over an already-small candidate
    # set (rerank_clause) - never as a standalone match query.
    def similarity_floor_query(vector)
      floor = Settings.semantic_search.min_similarity
      "{!vectorSimilarity f=embedding_vector minReturn=#{floor}}#{vector_literal(vector)}"
    end

    # Intersecting with the bounded KNN clause caps the floor's cost instead
    # of letting it scan the whole collection.
    def knn_match_clause(vector)
      knn = knn_query(vector)
      return knn unless min_similarity_floor?

      { bool: { must: [knn, similarity_floor_query(vector)] } }
    end

    # Reranking only scores the reRankDocs candidates already selected, so
    # the floor is cheap here regardless.
    def rerank_clause(vector)
      min_similarity_floor? ? similarity_floor_query(vector) : knn_query(vector)
    end

    def apply_vector_query(solr_parameters, knn)
      solr_parameters[:json] ||= {}
      # A raw KNN string needs wrapping in a bool clause so Solr parses it
      # with the `lucene` parser (which honors the `{!knn}` local param); a
      # floor-filtered match clause is already a structured bool query.
      solr_parameters[:json][:query] = knn.is_a?(String) ? { bool: { must: [knn] } } : knn
      # The KNN query is the whole query now; drop the plain lexical q.
      solr_parameters.delete(:q)
    end

    def apply_hybrid_query(solr_parameters, query, vector)
      apply_rerank_hybrid(solr_parameters, query, knn_match_clause(vector), rerank_clause(vector))
    end

    def apply_rerank_hybrid(solr_parameters, query, knn_match, knn_rerank)
      solr_parameters[:json] ||= {}
      solr_parameters[:json][:query] = {
        bool: { should: [{ edismax: { query: query } }, knn_match] }
      }
      solr_parameters[:rq] = '{!rerank reRankQuery=$knn_rq ' \
                             "reRankDocs=#{Settings.semantic_search.rerank_docs} " \
                             "reRankWeight=#{Settings.semantic_search.rerank_weight}}"
      solr_parameters[:knn_rq] = knn_rerank
      # The lexical query is now carried by json.query; drop the plain q so Solr
      # does not also run it as a separate top-level query.
      solr_parameters.delete(:q)
    end
  end
end
