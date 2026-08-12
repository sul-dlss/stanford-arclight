# frozen_string_literal: true

require 'digest'

# Namespace + feature-flag/config entry point for semantic (vector) search.
#
# This file is intentionally free of any hard Rails dependency so it can be
# `require`d from the Traject indexing process, which runs standalone (see
# IndexEadJob, which shells out to `bundle exec traject` without booting Rails).
#
# Two independent, environment-scoped feature flags gate the whole feature and
# both default to OFF:
#
#   * ENABLE_SEMANTIC_INDEXING - gates embedding generation at index time
#   * ENABLE_SEMANTIC_QUERY    - gates KNN querying / semantic result blending
#
# The flags are wired through the app's existing `config` gem convention
# (config/settings*.yml, which read the ENV vars via ERB) when Rails/Settings
# is available. When Settings is not loaded (the Traject process), we fall back
# to reading the same ENV vars directly, so both processes agree on one source
# of truth: the ENV var.
module SemanticSearch
  # Embedding model configuration. These MUST stay identical between index-time
  # and query-time embedding or KNN similarity is meaningless.
  MODEL = 'gemini-embedding-2'
  # Matryoshka truncation via output_dimensionality: 768 is the established
  # quality/size tradeoff from prior internal experimentation.
  DIMENSIONS = 768

  # Version of the embedding "recipe" - which fields feed TextBuilder, plus any
  # normalization and the target dimensions. Stamped onto each vector doc
  # (embedding_schema_version_ssi) and bumped when the recipe changes, so a
  # re-embed campaign can target the docs still on an old version. Independent of
  # the model, which is tracked separately (embedding_model_ssi).
  EMBED_SCHEMA_VERSION = '1'

  # Solr's JSON parser (Noggit) rejects float literals with too many digits
  # (e.g. Ruby's expanded `0.0000020771296931343386`). Vectors are float32, so
  # rounding to 7 decimal places is lossless at that precision and keeps the
  # serialized numbers short enough for Solr - both at index time and in the KNN
  # query. See SemanticSearch.solr_vector.
  SOLR_VECTOR_PRECISION = 7

  module_function

  # The embedding model to call. Defaults to MODEL (gemini-embedding-2); override
  # with SEMANTIC_SEARCH_EMBEDDING_MODEL to evaluate an alternative (e.g.
  # text-multilingual-embedding-002, which - unlike gemini on this gateway -
  # supports true multi-input batching and honors task_type). MUST match between
  # index time and query time, and a change invalidates existing vectors (keep
  # each model's embeddings in its own cache file, or clear the cache).
  def embedding_model
    value = ENV.fetch('SEMANTIC_SEARCH_EMBEDDING_MODEL', nil)
    value.to_s.empty? ? MODEL : value
  end

  # Which gateway transport a model is reached through. The gateway exposes two:
  #
  #   * an OpenAI-compatible /embeddings route, which fronts the Vertex
  #     text-embedding models, and
  #   * a native Gemini pass-through (/gemini/v1beta, generativelanguage rather
  #     than Vertex) for the gemini-embedding family.
  #
  # The distinction is BATCHING, not task types. The OpenAI route silently
  # collapses a multi-input gemini request to a single embedding (20 in, 1 out);
  # the pass-through batches properly. Every gemini-* model goes through it.
  #
  # NOTE: both transports send an asymmetric retrieval task type, but
  # gemini-embedding-2 IGNORES it (cosine 1.000000 between RETRIEVAL_QUERY and
  # RETRIEVAL_DOCUMENT on BOTH routes) - its vectors are symmetric. The earlier
  # TASK_TYPE_MODELS allowlist was dropped because sending an inert parameter is
  # harmless and the code path is shared with models that do honour it.
  def gemini_native?
    embedding_model.start_with?('gemini-')
  end

  # Round a vector to a Solr-safe (float32-precision) representation before it is
  # serialized into an update document or a `{!knn}` query.
  #
  # @param vector [Array<Float>]
  # @return [Array<Float>]
  def solr_vector(vector)
    vector.map { |value| value.round(SOLR_VECTOR_PRECISION) }
  end

  # SHA256 of the exact embedded text - the content-addressed cache key
  # (EmbeddingCache::Sqlite#key), exposed so index-time provenance
  # (embedding_input_hash_ssm) stays in lockstep with the cache. Lets a re-embed
  # detect drift: when a finding aid's text changes, this hash changes.
  def input_hash(text)
    Digest::SHA256.hexdigest(text.to_s)
  end

  # @return [Boolean] whether the indexing pipeline should generate + write
  #   embeddings. Defaults to false.
  def indexing_enabled?
    flag('semantic_search.indexing_enabled', 'ENABLE_SEMANTIC_INDEXING')
  end

  # @return [Boolean] whether the controller should issue KNN queries and blend
  #   semantic results. Defaults to false.
  def query_enabled?
    flag('semantic_search.query_enabled', 'ENABLE_SEMANTIC_QUERY')
  end

  # @return [Boolean] whether per-request relevance-tuning overrides (URL params
  #   + the dev tuning panel) are honored. A dev/stage-only affordance for the
  #   relevance-eval workflow. Defaults to false; NEVER enable in production.
  #   Gated by its own flag (not Rails.env) because stage runs as the production
  #   Rails environment here.
  def tuning_enabled?
    flag('semantic_search.tuning_enabled', 'SEMANTIC_SEARCH_TUNING')
  end

  # @return [Boolean] whether record pages show a vector-based "Related
  #   collections" panel (SemanticSearch::SimilarDocuments). Independent of
  #   query_enabled? on purpose: this reads stored vectors and makes no gateway
  #   call, so it can be enabled without changing search behaviour at all.
  def related_enabled?
    flag('semantic_search.related_enabled', 'ENABLE_SEMANTIC_RELATED')
  end

  # @return [Boolean] whether "Related collections" fuses a LEXICAL arm (shared
  #   creator / subject headings / names) into the vector KNN, rather than
  #   ranking on the embedding alone. PROTOTYPE, default off.
  #
  #   Motivated by measurement, not theory: on 236 archivist-authored cases (EAD
  #   relatedmaterial), 10% of the stated relationships are found by NEITHER
  #   embedding model, and the union of both models beats the better one by only
  #   +0.030 - so the ceiling for any better embedding is tiny. Those misses are
  #   provenance-shaped ("split across two accessions"), which a 37-character
  #   title cannot express but a shared creator string states outright. Different
  #   evidence, not better evidence of the same kind.
  def related_lexical_enabled?
    flag('semantic_search.related_lexical_enabled', 'ENABLE_SEMANTIC_RELATED_LEXICAL')
  end

  # @return [Boolean] whether hybrid search fuses the lexical + vector queries
  #   with Solr's native RRF `combiner` (one request, correct facets, rank-based
  #   fusion) instead of the default `bool.should` + reRank blend. The combiner
  #   ships in Solr 9.11 / 10.1 (SOLR-17319); on our 9.10 it is silently ignored
  #   and returns match-all, so this MUST stay off until Solr is upgraded. Wired
  #   up now so the switch is a single flag flip post-upgrade. Defaults to false.
  def rrf_combiner_enabled?
    flag('semantic_search.rrf_combiner_enabled', 'SEMANTIC_SEARCH_RRF_COMBINER')
  end

  # Reads a boolean flag, preferring the `config` gem Settings (Rails context)
  # and falling back to ENV (standalone Traject context). Both resolve to the
  # same ENV var, so the two contexts never disagree.
  #
  # @param settings_path [String] dotted path under Settings, e.g. "a.b.c"
  # @param env_key [String] the ENV var backing the setting
  # @return [Boolean]
  def flag(settings_path, env_key)
    value = setting(settings_path)
    value = ENV.fetch(env_key, nil) if value.nil?
    truthy?(value)
  end

  # Safely dig into Settings without raising when Settings is undefined (e.g.
  # in the Traject process) or a key is missing.
  #
  # @return [Object, nil]
  def setting(dotted_path)
    return nil unless defined?(Settings)

    dotted_path.split('.').reduce(Settings) do |node, key|
      return nil unless node.respond_to?(key)

      node.public_send(key)
    end
  rescue StandardError
    nil
  end

  # @return [Boolean] loose truthiness usable for both real booleans and the
  #   strings that arrive from ENV ("true"/"1"/"yes"/"on").
  def truthy?(value)
    case value
    when true then true
    when false, nil then false
    else
      %w[true 1 yes on t].include?(value.to_s.strip.downcase)
    end
  end
end
