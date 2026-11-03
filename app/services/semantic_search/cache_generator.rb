# frozen_string_literal: true

require 'digest'
require 'logger'

module SemanticSearch
  # Batches document texts and populates a writable EmbeddingCache, for the
  # one-time "generate all embeddings" pass (no Solr). Fed one text at a time
  # (from the Traject per-record hook), it:
  #
  #   * skips texts already in the cache (so a re-run resumes, re-paying nothing),
  #   * de-duplicates identical texts within a batch (content-addressed),
  #   * embeds a whole batch in one #embed_batch call (far fewer API round-trips
  #     than per-doc), and stores the vectors.
  #
  # A batch that fails to embed is logged and dropped (its texts stay uncached),
  # so a re-run retries just those. Call #flush at the end to drain the last
  # partial batch. Rails-free (runs in the Traject process).
  #
  # CONCURRENCY: the embedding call deliberately runs OUTSIDE the mutex. The
  # buffer, the counters and the SQLite writes are all serialized, but the HTTP
  # round-trip - which is essentially the whole cost of the run - is not, so N
  # Traject worker threads produce N concurrent requests rather than queueing
  # behind one. Holding the lock across the request would make extra threads
  # pure overhead. Traject's processing_thread_pool governs N (see
  # lib/traject/sul_config.rb)
  class CacheGenerator
    DEFAULT_BATCH_SIZE = 100

    def initialize(cache:, embedding_service: EmbeddingService.new,
                   batch_size: DEFAULT_BATCH_SIZE, logger: default_logger)
      @cache = cache
      @embedding_service = embedding_service
      @batch_size = batch_size
      @logger = logger
      @buffer = {} # hash => text
      @stats = { seen: 0, embedded: 0, skipped: 0, failed: 0 }
      # add/flush are called from Traject's worker threads; serialize the shared
      # buffer + counters.
      @mutex = Mutex.new
    end

    # @param text [String] the embed text for one doc
    def add(text)
      return if text.to_s.empty? # core Ruby only (Traject process)

      embed_and_store(@mutex.synchronize { buffer(text) })
    end

    # Embed and store the buffered batch.
    def flush
      embed_and_store(@mutex.synchronize { take_batch })
    end

    # @return [Hash] running counters
    def stats
      @mutex.synchronize { @stats.dup }
    end

    private

    # Record one text and hand back a batch when the buffer is full. MUST be
    # called with the mutex held.
    #
    # @return [Array<String>, nil] a batch to embed, or nil
    def buffer(text)
      @stats[:seen] += 1
      if @cache.fetch(text)
        @stats[:skipped] += 1
        return nil
      end

      @buffer[Digest::SHA256.hexdigest(text)] = text
      take_batch if @buffer.size >= @batch_size
    end

    # Detach the buffered texts so the caller owns them and no other thread can
    # embed them too. MUST be called with the mutex held.
    #
    # @return [Array<String>, nil] the texts, or nil when there is nothing to do
    def take_batch
      return nil if @buffer.empty?

      texts = @buffer.values
      @buffer.clear
      texts
    end

    # Embeds OUTSIDE the mutex (see the class comment) and re-takes it only to
    # record the results.
    def embed_and_store(texts)
      # rubocop:disable Rails/Blank -- no ActiveSupport here; this runs in the
      # Rails-free Traject process, so `blank?` is not defined.
      return if texts.nil? || texts.empty?
      # rubocop:enable Rails/Blank

      vectors = @embedding_service.embed_batch(texts, task_type: EmbeddingService::DOCUMENT_TASK_TYPE)
      @mutex.synchronize do
        @stats[:embedded] += store_vectors(texts, vectors)
        log_progress
      end
    rescue StandardError => e
      @mutex.synchronize { @stats[:failed] += texts.size }
      @logger&.warn("[SemanticSearch] embedding batch of #{texts.size} failed: " \
                    "#{e.class}: #{e.message} (retryable on re-run)")
    end

    # @return [Integer] number actually stored. Called with the mutex held: the
    #   SQLite handle is shared and its writes stay serialized even though the
    #   embedding requests do not.
    def store_vectors(texts, vectors)
      stored = 0
      texts.each_with_index do |text, i|
        next unless vectors[i]&.any?

        @cache.store(text, vectors[i])
        stored += 1
      end
      stored
    end

    def log_progress
      @logger&.info("[SemanticSearch] embeddings generated: #{@stats[:embedded]} " \
                    "(seen #{@stats[:seen]}, skipped cached #{@stats[:skipped]}, failed #{@stats[:failed]})")
    end

    def default_logger
      return Rails.logger if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Logger.new($stderr)
    end
  end
end
