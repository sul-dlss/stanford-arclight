# frozen_string_literal: true

require 'sqlite3'
require 'digest'

module SemanticSearch
  module EmbeddingCache
    # Content-addressed embedding cache backed by a single SQLite file:
    #   SHA256(embed text)  ->  the doc's vector (float32 blob)
    #
    # Two modes:
    #   * writable  - local generation: creates the file, WAL, INSERT OR IGNORE.
    #   * read-only - serving: opened `immutable=1` so SQLite skips locking. Safe
    #     for a static, shipped file, NFS-friendly, and fine for many concurrent
    #     readers (across hosts). NEVER write to the file over NFS.
    #
    # Rails-free (the sqlite3 gem is in the bundle) so it works in the Traject
    # indexing process. Keyed on content, so an unchanged doc re-uses its vector
    # on every reindex/harvest, and a changed doc (new hash) re-embeds itself.
    #
    # Vectors are stored as little-endian float32 ('e') - the precision Solr
    # stores anyway - so no extra loss beyond what the index already uses.
    class Sqlite
      def initialize(path, writable: false)
        @writable = writable
        @db = open_database(path)
        create_schema if writable
        # A SQLite3::Database is shared across Traject's worker threads; serialize
        # all access (it is not safe to interleave statements on one connection).
        @mutex = Mutex.new
      end

      # @param text [String]
      # @return [Array<Float>, nil] the cached vector, or nil on a miss
      def fetch(text)
        blob = @mutex.synchronize { @db.get_first_value('SELECT vec FROM embeddings WHERE hash = ?', key(text)) }
        blob&.unpack('e*')
      end

      # Store a vector for text. No-op in read-only mode. First writer wins
      # (INSERT OR IGNORE) so concurrent generators don't clobber each other.
      #
      # @param text [String]
      # @param vector [Array<Float>]
      def store(text, vector)
        return unless @writable

        blob = SQLite3::Blob.new(vector.map(&:to_f).pack('e*'))
        @mutex.synchronize do
          @db.execute('INSERT OR IGNORE INTO embeddings (hash, vec) VALUES (?, ?)', [key(text), blob])
        end
        nil
      end

      def writable?
        @writable
      end

      # @return [Integer] number of cached vectors
      def size
        @mutex.synchronize { @db.get_first_value('SELECT COUNT(*) FROM embeddings') }
      end

      def close
        @mutex.synchronize { @db&.close }
      end

      private

      def key(text)
        Digest::SHA256.hexdigest(text)
      end

      def open_database(path)
        return open_writable(path) if @writable

        SQLite3::Database.new("file:#{path}?immutable=1",
                              flags: SQLite3::Constants::Open::READONLY | SQLite3::Constants::Open::URI)
      end

      def open_writable(path)
        db = SQLite3::Database.new(path)
        db.busy_timeout = 5000
        db.execute('PRAGMA journal_mode=WAL')
        db.execute('PRAGMA synchronous=NORMAL')
        db
      end

      def create_schema
        @db.execute('CREATE TABLE IF NOT EXISTS embeddings (hash TEXT PRIMARY KEY, vec BLOB NOT NULL)')
      end
    end
  end
end
