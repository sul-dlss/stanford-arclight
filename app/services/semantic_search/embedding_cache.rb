# frozen_string_literal: true

module SemanticSearch
  # A persistent, content-addressed document-embedding cache: generate the
  # ~1.19M vectors once (paying the embedding cost), then reuse them on every
  # reindex/harvest for free. Keyed on SHA256(embed text), so an unchanged doc
  # is a cache hit and a changed doc re-embeds itself.
  #
  # This is the seam: today it's a SQLite file (Sqlite); a Postgres-backed adapter
  # could implement the same `fetch(text)` / `store(text, vector)` / `writable?`
  # contract later without touching the Indexer.
  #
  # Config (ENV, so it's identical in the Rails and Traject processes):
  #   SEMANTIC_SEARCH_EMBEDDING_CACHE       - path to the SQLite file; unset = off
  #   SEMANTIC_SEARCH_EMBEDDING_CACHE_WRITE - truthy for generation (write mode)
  module EmbeddingCache
    module_function

    # @return [Sqlite, nil] a cache, or nil when disabled / (read-only) missing
    def build(path: ENV.fetch('SEMANTIC_SEARCH_EMBEDDING_CACHE', nil),
              writable: SemanticSearch.truthy?(ENV.fetch('SEMANTIC_SEARCH_EMBEDDING_CACHE_WRITE', nil)),
              logger: nil)
      # core Ruby only (no ActiveSupport blank?) - runs in the Traject process
      return nil if path.to_s.empty?
      return Sqlite.new(path, writable: true) if writable

      unless File.exist?(path)
        logger&.warn("[SemanticSearch] embedding cache not found at #{path}; embedding without a cache")
        return nil
      end

      Sqlite.new(path, writable: false)
    end
  end
end
