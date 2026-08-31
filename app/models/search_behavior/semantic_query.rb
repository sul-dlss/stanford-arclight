# frozen_string_literal: true

module SearchBehavior
  # SearchBuilder processor chain behavior for semantic (vector) search.
  #
  module SemanticQuery
    # search_field values that trigger semantic search, mapped to query mode.
    SEMANTIC_SEARCH_FIELDS = { 'hybrid' => :hybrid, 'semantic' => :vector }.freeze

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
    # docs at/above the cosine cutoff).
    def vector_query(vector)
      literal = "[#{SemanticSearch.solr_vector(vector).join(',')}]"
      floor = Settings.semantic_search.min_similarity
      return "{!vectorSimilarity f=embedding_vector minReturn=#{floor}}#{literal}" if floor.positive?

      "{!knn f=embedding_vector topK=#{Settings.semantic_search.top_k}}#{literal}"
    end

    def apply_vector_query(solr_parameters, knn)
      solr_parameters[:json] ||= {}
      # Wrap the KNN string in a bool clause so Solr parses it with the `lucene`
      # parser (which honors the `{!knn}` local param).
      solr_parameters[:json][:query] = { bool: { must: [knn] } }
      # The KNN query is the whole query now; drop the plain lexical q.
      solr_parameters.delete(:q)
    end

    def apply_hybrid_query(solr_parameters, query, vector)
      apply_rerank_hybrid(solr_parameters, query, vector_query(vector))
    end

    def apply_rerank_hybrid(solr_parameters, query, knn)
      solr_parameters[:json] ||= {}
      solr_parameters[:json][:query] = {
        bool: { should: [{ edismax: { query: query } }, knn] }
      }
      solr_parameters[:rq] = '{!rerank reRankQuery=$knn_rq ' \
                             "reRankDocs=#{Settings.semantic_search.rerank_docs} " \
                             "reRankWeight=#{Settings.semantic_search.rerank_weight}}"
      solr_parameters[:knn_rq] = knn
      # The lexical query is now carried by json.query; drop the plain q so Solr
      # does not also run it as a separate top-level query.
      solr_parameters.delete(:q)
    end
  end
end
