# frozen_string_literal: true

require 'digest'

# Namespace + config entry point for semantic (vector) search.
#
# This file is intentionally free of any hard Rails dependency so it can be
# `require`d from the Traject indexing process.
#
# Indexing fails soft: with no API key,
# documents are indexed without a vector and a warning is logged.
module SemanticSearch
  MODEL = 'text-multilingual-embedding-002'
  # The model's native width; also the width of the Solr field.
  DIMENSIONS = 768

  # Version of the embedding "recipe" - which fields feed TextBuilder, plus any
  # normalization and the target dimensions. Stamped onto each vector doc
  # (embedding_schema_version_ssi) and bumped when the recipe changes, so a
  # re-embed campaign can target the docs still on an old version. Independent of
  # the model, which is tracked separately (embedding_model_ssi).
  EMBED_SCHEMA_VERSION = '1'

  # Solr's JSON parser (Noggit) rejects float literals with too many digits
  SOLR_VECTOR_PRECISION = 7

  module_function

  def embedding_model
    value = ENV.fetch('SEMANTIC_SEARCH_EMBEDDING_MODEL', nil)
    value.to_s.empty? ? MODEL : value
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
  # (embedding_input_hash_ssm) stays in sync with the cache. Lets a re-embed
  # detect drift: when a finding aid's text changes, this hash changes.
  def input_hash(text)
    Digest::SHA256.hexdigest(text.to_s)
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
