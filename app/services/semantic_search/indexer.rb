# frozen_string_literal: true

require 'logger'

module SemanticSearch
  # Index-time glue used from the Traject configs (Rails-free). Given a Traject
  # `output_hash` for one Solr doc, builds the embed text, resolves its vector
  # (cache first, then the embedding API), and writes it into `embedding_vector`
  # on the same doc.
  #
  # If an EmbeddingCache is configured (SEMANTIC_SEARCH_EMBEDDING_CACHE), a cache
  # hit avoids the API entirely; a miss calls the API and, in write mode, stores
  # the result. The service and cache are memoized once per process.
  #
  # Fails soft: any embedding/config/API error is logged and swallowed so the
  # document still indexes without a vector.
  module Indexer
    VECTOR_FIELD = 'embedding_vector'
    # Provenance/versioning fields written alongside the vector. Suffixes map to
    # our Solr dynamic fields: *_ssi = string stored+indexed single, *_ssm =
    # string stored-only multi, *_is = pint stored single. Values are assigned as
    # one-element arrays, matching the hashed_id_ssi convention in the traject
    # configs. Model + schema-version are indexed so a re-embed can `fq` on them.
    MODEL_FIELD = 'embedding_model_ssi'
    INPUT_HASH_FIELD = 'embedding_input_hash_ssm'
    SCHEMA_VERSION_FIELD = 'embedding_schema_version_ssi'
    DIMENSIONS_FIELD = 'embedding_dimensions_is'

    module_function

    # @param output_hash [Hash] Traject context output_hash for one doc
    # @param embedding_service [EmbeddingService]
    # @param cache [EmbeddingCache::Sqlite, nil]
    # @param logger [Logger]
    # @return [void] mutates output_hash in place
    def add_embedding!(output_hash, embedding_service: service, cache: cache_store, logger: default_logger)
      write_embedding(output_hash, embedding_service, cache)
    rescue EmbeddingService::Error => e
      # Expected failure modes (missing creds, API/timeout): skip the vector.
      logger&.warn("[SemanticSearch] skipped embedding for #{doc_id(output_hash)}: #{e.class}: #{e.message}")
    rescue StandardError => e
      # Never let an unexpected error take down the indexing job.
      logger&.error("[SemanticSearch] unexpected embedding error for #{doc_id(output_hash)}: #{e.class}: #{e.message}")
    end

    def write_embedding(output_hash, embedding_service, cache)
      text = TextBuilder.new(output_hash).call
      # core Ruby only (no ActiveSupport blank?/present?) - Traject process
      return if text.to_s.empty?

      # Generation pass: buffer the text for batched embedding into the cache and
      # skip the (irrelevant) Solr vector - see SEMANTIC_SEARCH_EMBEDDING_CACHE_GENERATE.
      return generator.add(text) if generating?

      vector = resolve_vector(text, embedding_service, cache)
      return unless vector&.any?

      output_hash[VECTOR_FIELD] = SemanticSearch.solr_vector(vector)
      add_metadata!(output_hash, text, vector)
    end

    # Stamp provenance next to the vector. The model reflects the CURRENT
    # configured model, so it is only accurate if the cache holds vectors from
    # that same model - the standing rule (rebuild the cache on a model change).
    # The stamp then also makes a violation of that rule detectable after the
    # fact. See EMBED_SCHEMA_VERSION for the recipe-version story.
    def add_metadata!(output_hash, text, vector)
      output_hash[MODEL_FIELD] = [SemanticSearch.embedding_model]
      output_hash[INPUT_HASH_FIELD] = [SemanticSearch.input_hash(text)]
      output_hash[SCHEMA_VERSION_FIELD] = [SemanticSearch::EMBED_SCHEMA_VERSION]
      output_hash[DIMENSIONS_FIELD] = [vector.length]
    end

    # Cache first; on a miss, embed and (in write mode) store.
    def resolve_vector(text, embedding_service, cache)
      cached = cache&.fetch(text)
      return cached if cached

      vector = embedding_service.embed(text, task_type: EmbeddingService::DOCUMENT_TASK_TYPE)
      cache.store(text, vector) if vector && cache&.writable?
      vector
    end

    # Memoized once per process (one Faraday connection, one cache handle).
    def service
      @service ||= EmbeddingService.new
    end

    def cache_store
      return @cache_store if defined?(@cache_store)

      # In a generation pass the read-through cache is unused, so don't build it.
      @cache_store = generating? ? nil : EmbeddingCache.build(logger: default_logger)
    end

    def generating?
      SemanticSearch.truthy?(ENV.fetch('SEMANTIC_SEARCH_EMBEDDING_CACHE_GENERATE', nil))
    end

    # The batch generator writes to the cache in write mode. Built once, and its
    # last partial batch is flushed when the process exits.
    def generator
      @generator ||= begin
        path = ENV.fetch('SEMANTIC_SEARCH_EMBEDDING_CACHE')
        gen = CacheGenerator.new(cache: EmbeddingCache::Sqlite.new(path, writable: true),
                                 embedding_service: service, batch_size: generate_batch_size,
                                 logger: default_logger)
        at_exit { gen.flush }
        gen
      end
    end

    # The generator buffers this many texts before embedding them in one flush.
    # Defaults to the service's OWN per-request size rather than a separate
    # constant: a buffer larger than one request turns each flush into several
    # sequential requests, which serializes work the threaded generation pass is
    # trying to overlap (measured ~7% of wall clock when the two were 100 vs 50).
    # Keeping them equal also means a failed batch drops exactly one request's
    # worth of texts, which a re-run retries.
    def generate_batch_size
      Integer(ENV.fetch('SEMANTIC_SEARCH_EMBED_BATCH_SIZE', service.batch_size))
    end

    def doc_id(output_hash)
      Array(output_hash['id']).first || '(unknown id)'
    end

    def default_logger
      return Rails.logger if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Logger.new($stderr)
    end
  end
end
