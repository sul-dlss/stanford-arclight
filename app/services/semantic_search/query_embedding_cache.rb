# frozen_string_literal: true

module SemanticSearch
  # Thin cache in front of EmbeddingService for query-string embeddings, so a
  # repeated search doesn't re-hit the gateway. Keyed on the normalized query
  # string (downcased, whitespace-collapsed) plus the model/dimensionality, so
  # a config change can never serve a stale-shape vector.
  #
  # Backed by Rails.cache (query-time only path, always inside Rails).
  class QueryEmbeddingCache
    DEFAULT_TTL = 12 * 60 * 60 # 12 hours

    def initialize(embedding_service: nil, cache: Rails.cache, ttl: DEFAULT_TTL)
      # Query-time embedding gets a TIGHT timeout: if the gateway is slow (we've
      # seen 11s spikes), fall back to keyword search (SearchBehavior::SemanticQuery
      # rescues the error) rather than freeze the whole request. Index-time keeps
      # EmbeddingService's long default for patient batch generation.
      @embedding_service = embedding_service || EmbeddingService.new(timeout: query_timeout)
      @cache = cache
      @ttl = ttl
    end

    # @param query [String]
    # @return [Array<Float>] the query embedding
    def embed(query)
      @cache.fetch(cache_key(query), expires_in: @ttl) do
        @embedding_service.embed(query, task_type: EmbeddingService::QUERY_TASK_TYPE)
      end
    end

    private

    # Seconds to wait for the query embedding before giving up and falling back
    # to keyword. Kept short so a slow gateway can't stall the search.
    #
    # Read via Settings, not ENV directly: this class is documented above as
    # always running inside a booted Rails process, unlike EmbeddingService
    # itself (shared with the Rails-free Traject path), which is why that class
    # still reads ENV.fetch directly and can't safely switch to Settings.
    def query_timeout
      Settings.semantic_search.query_embed_timeout
    end

    def cache_key(query)
      normalized = query.to_s.strip.downcase.gsub(/\s+/, ' ')
      # Include the ACTUAL model (not the default constant) so switching models
      # never serves a stale-shape/other-model vector from cache.
      "semantic_search/query_embedding/#{SemanticSearch.embedding_model}/#{DIMENSIONS}/#{normalized}"
    end
  end
end
