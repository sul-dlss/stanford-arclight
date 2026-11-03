# frozen_string_literal: true

require 'faraday'
require 'json'
require 'logger'

module SemanticSearch
  # Client for embeddings via the Stanford LiteLLM AI gateway
  # (https://dlss-aigateway-prod.stanford.edu).
  #
  # Used from BOTH contexts:
  #   * index time (Traject, Rails-free) - #embed_batch over document text
  #   * query time (Rails controller)    - #embed over the user's query string
  #
  # so it must stay free of hard Rails dependencies.
  #
  # One transport: the gateway's OpenAI-compatible `POST /embeddings`, bearer
  # auth, with `task_type` passed as a non-OpenAI param that the gateway forwards
  # to Vertex. The asymmetry is not cosmetic - the same text embedded as a query
  # and as a document differs by ~0.86 cosine - so it must not vary between index
  # time and query time.
  #
  # Config is read from ENV so the value is identical in the Rails and Traject
  # processes:
  #   SEMANTIC_SEARCH_EMBEDDING_API_KEY  - required; the gateway key
  #   SEMANTIC_SEARCH_EMBEDDING_API_BASE - override the gateway base (optional);
  #                                        applies to BOTH transports
  #   SEMANTIC_SEARCH_EMBED_BATCH_SIZE   - inputs per request (optional)
  #
  # Max input is 8,192 tokens, so we clamp very long inputs by characters.
  class EmbeddingService # rubocop:disable Metrics/ClassLength
    class Error < StandardError; end
    # Raised when required config (the API key) is absent. Callers at index time
    # rescue this so a doc still indexes (just without a vector).
    class ConfigurationError < Error; end
    # Raised on transport/API failures (HTTP error, timeout, malformed body).
    class ApiError < Error; end

    # Raised on HTTP 429. Retryable: the generation path retries with backoff;
    # the query path lets it propagate (as an ApiError) and falls back to keyword.
    class RateLimitError < ApiError
      attr_reader :retry_after

      def initialize(message, retry_after: nil)
        super(message)
        @retry_after = retry_after
      end
    end

    # Asymmetric retrieval task types. Both transports send one; WHICH one is the
    # caller's choice (documents vs queries).
    DOCUMENT_TASK_TYPE = 'RETRIEVAL_DOCUMENT'
    QUERY_TASK_TYPE = 'RETRIEVAL_QUERY'

    # Inputs sent per /embeddings request.
    DEFAULT_BATCH_SIZE = 100

    DEFAULT_ENDPOINT = 'https://dlss-aigateway-prod.stanford.edu'
    DEFAULT_TIMEOUT = 30

    # Clamp on input length. The model's own limit is ~2,048
    # tokens and Vertex truncates beyond it server-side anyway; in this corpus
    # only ~0.2% of collection records are long enough to reach either. NOTE the
    # clamp happens AFTER the cache key is computed, so changing it does not
    # invalidate cached vectors - clear the cache if you need them regenerated.
    MAX_INPUT_CHARS = 30_000

    # @param logger [Logger] falls back to Rails.logger when present, else stderr
    # @param timeout [Integer] per-request timeout in seconds
    def initialize(logger: default_logger, timeout: DEFAULT_TIMEOUT)
      @logger = logger
      @timeout = timeout
    end

    # Embed a single string (query-time path).
    #
    # @param text [String]
    # @param task_type [String] sent only if the model accepts task types
    # @return [Array<Float>] a DIMENSIONS-length vector
    def embed(text, task_type: QUERY_TASK_TYPE)
      embed_batch([text], task_type: task_type).first
    end

    # Embed many strings in one OpenAI-style /embeddings request per batch.
    #
    # @param texts [Array<String>]
    # @param task_type [String] RETRIEVAL_DOCUMENT / RETRIEVAL_QUERY; included in
    #   the request only when the configured model accepts task types
    # @return [Array<Array<Float>>] one 768-dim vector per input, aligned
    def embed_batch(texts, task_type: DOCUMENT_TASK_TYPE)
      texts = Array(texts)
      return [] if texts.empty?

      token_batches(texts).flat_map do |slice|
        request_embeddings(slice, task_type)
      end
    end

    # Inputs this service will put in ONE request (before the token budget
    # splits it further). Public so callers that buffer work can size their
    # buffer to match: handing #embed_batch more than this silently becomes
    # several SEQUENTIAL requests, which serializes work a caller may have
    # intended to run concurrently. See Indexer#generate_batch_size.
    #
    # @return [Integer]
    def batch_size
      Integer(ENV.fetch('SEMANTIC_SEARCH_EMBED_BATCH_SIZE', DEFAULT_BATCH_SIZE))
    end

    private

    attr_reader :logger, :timeout

    # Group inputs into requests that respect BOTH the input-count cap
    # (batch_size) and the model's per-request TOKEN budget. The Vertex batch
    # endpoint caps total tokens per request (text-multilingual-embedding-002:
    # 20,000 across all inputs), which a fixed count exceeds when docs run long -
    # so we also cap by an estimated token sum kept under the hard limit. Token
    # count is estimated from characters (chars_per_token) since there's no
    # tokenizer in the Rails-free indexing process; CJK-heavy corpora may need a
    # smaller SEMANTIC_SEARCH_CHARS_PER_TOKEN.
    def token_batches(texts) # rubocop:disable Metrics/MethodLength
      batches = [[]]
      tokens = 0
      texts.each do |text|
        est = estimated_tokens(text)
        if full?(batches.last, tokens, est)
          batches << []
          tokens = 0
        end
        batches.last << text
        tokens += est
      end
      batches.reject(&:empty?)
    end

    def full?(batch, tokens, next_tokens)
      return false if batch.empty?

      batch.size >= batch_size || tokens + next_tokens > token_budget
    end

    def estimated_tokens(text)
      (text.length / chars_per_token.to_f).ceil
    end

    # Conservative defaults vs the model's 20,000-tokens/request hard limit:
    # archival metadata (names, dates, numbers, foreign terms) tokenizes denser
    # than plain prose - observed ~3 chars/token, not the ~4 rule of thumb - so
    # we estimate at 3 and keep the budget well under 20k. Both are tunable;
    # CJK-heavy corpora may need chars_per_token as low as 2.
    def token_budget
      Integer(ENV.fetch('SEMANTIC_SEARCH_EMBED_TOKEN_BUDGET', 12_000))
    end

    def chars_per_token
      Integer(ENV.fetch('SEMANTIC_SEARCH_CHARS_PER_TOKEN', 3))
    end

    def request_embeddings(texts, task_type)
      attempt = 0
      begin
        send_embed_request(texts, task_type)
      rescue RateLimitError => e
        raise if (attempt += 1) > max_retries

        wait_before_retry(e, attempt)
        retry
      rescue Faraday::Error => e
        raise ApiError, "Embedding request failed: #{e.class}: #{e.message}"
      end
    end

    # Wait at least our exponential backoff, and longer if the gateway's
    # Retry-After asks for more. Crucially we never wait LESS: some gateways send
    # `Retry-After: 0`, and honoring that literally (0 is truthy in Ruby) means
    # an instant retry that keeps the rate-limit window from ever draining
    def wait_before_retry(error, attempt)
      wait = [error.retry_after.to_i, backoff(attempt)].max
      logger&.warn("[SemanticSearch] rate limited (429); retry #{attempt}/#{max_retries} in #{wait}s")
      sleep(wait)
    end

    def send_embed_request(texts, task_type)
      response = post_embed(embed_body(texts, task_type))
      raise rate_limit_error(response) if response.status == 429
      raise ApiError, "Embedding gateway returned #{response.status}: #{response.body}" unless response.success?

      parse_embeddings(response.body, texts.size)
    end

    # OpenAI-style /embeddings request body. task_type is a non-OpenAI param the
    # gateway forwards to Vertex.
    def embed_body(texts, task_type)
      { model: SemanticSearch.embedding_model, input: texts.map { |t| clamp(t) },
        encoding_format: 'float', task_type: task_type }
    end

    def rate_limit_error(response)
      retry_after = Integer(response.headers['retry-after'], exception: false)
      RateLimitError.new("Embedding gateway rate limit (429): #{response.body}", retry_after: retry_after)
    end

    def post_embed(body)
      connection.post('/embeddings') do |req|
        req.headers['Authorization'] = "Bearer #{api_key}"
        req.headers['Content-Type'] = 'application/json'
        req.body = JSON.generate(body)
      end
    end

    def parse_embeddings(raw, expected)
      parsed = raw.is_a?(String) ? JSON.parse(raw) : raw
      data = parsed.fetch('data').sort_by { |row| row.fetch('index') }
      # Reject partial responses (e.g. a rate-limited 200 with fewer rows) so the
      # whole batch is retried rather than silently under-stored.
      raise ApiError, "expected #{expected} embeddings, got #{data.size}" unless data.size == expected

      data.map { |row| to_dimensions(row.fetch('embedding')) }
    rescue KeyError, JSON::ParserError => e
      raise ApiError, "Unexpected embedding response shape: #{e.message}"
    end

    # Retries are opt-in (0 by default): the query path fails fast, generation
    # sets SEMANTIC_SEARCH_EMBED_MAX_RETRIES to ride out rate limits.
    def max_retries
      Integer(ENV.fetch('SEMANTIC_SEARCH_EMBED_MAX_RETRIES', 0))
    end

    def backoff(attempt)
      [2**attempt, 60].min
    end

    # Matryoshka truncation: keep the first DIMENSIONS values and L2-normalize so
    # the truncated vector is a valid unit embedding regardless of the gateway's
    # native output size. For the configured model the response is already
    # DIMENSIONS wide, so this is a guard rather than a transformation.
    def to_dimensions(values)
      raise ApiError, "embedding has #{values.length} dims (< #{DIMENSIONS})" if values.length < DIMENSIONS

      truncated = values.first(DIMENSIONS)
      norm = Math.sqrt(truncated.sum { |v| v * v })
      norm.zero? ? truncated : truncated.map { |v| v / norm }
    end

    def clamp(text)
      max = Integer(ENV.fetch('SEMANTIC_SEARCH_MAX_INPUT_CHARS', MAX_INPUT_CHARS))
      text.length > max ? text[0, max] : text
    end

    # Memoized PER THREAD, not per instance: the bulk generator shares one
    # service across Traject worker threads (see CacheGenerator), and a Faraday
    # connection is not meant to be driven concurrently. Keyed by object_id so
    # two services in one thread don't collide.
    def connection
      Thread.current[connection_key] ||= build_connection
    end

    def connection_key
      @connection_key ||= :"semantic_search_embedding_connection_#{object_id}"
    end

    def build_connection
      Faraday.new(url: api_base) do |f|
        f.options.timeout = timeout
        f.options.open_timeout = timeout
        f.adapter Faraday.default_adapter
      end
    end

    def api_base
      ENV.fetch('SEMANTIC_SEARCH_EMBEDDING_API_BASE', DEFAULT_ENDPOINT)
    end

    def api_key
      key = ENV.fetch('SEMANTIC_SEARCH_EMBEDDING_API_KEY', nil)
      return key unless key.to_s.empty?

      raise ConfigurationError, 'SEMANTIC_SEARCH_EMBEDDING_API_KEY is not set'
    end

    def default_logger
      return Rails.logger if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Logger.new($stderr)
    end
  end
end
