# frozen_string_literal: true

require 'faraday'
require 'json'
require 'logger'

module SemanticSearch
  # Client for embeddings via the Stanford LiteLLM AI gateway
  # (https://dlss-aigateway-prod.stanford.edu). We talk to the gateway, so
  # there's no Google/Vertex auth here - just the proxy's own key.
  #
  # Used from BOTH contexts:
  #   * index time (Traject, Rails-free) - #embed_batch over document text
  #   * query time (Rails controller)    - #embed over the user's query string
  #
  # so it must stay free of hard Rails dependencies.
  #
  # TWO TRANSPORTS, chosen by model (SemanticSearch.gemini_native?):
  #
  #   * Vertex text-embedding models -> OpenAI-compatible POST /embeddings,
  #     bearer auth, `task_type` as a non-OpenAI param the gateway forwards.
  #     This route does not accept a `dimensions` param, so vectors come back at
  #     native width and are truncated to 768 client-side.
  #   * gemini-embedding-* -> native pass-through POST
  #     /gemini/v1beta/models/<model>:batchEmbedContents (generativelanguage, not
  #     Vertex), key as a `?key=` query param, `taskType` and a real
  #     `outputDimensionality` per request - so 768 is asked for directly rather
  #     than truncated to.
  #
  # WHY THE PASS-THROUGH EXISTS: BATCHING. The OpenAI route does not batch
  # gemini-embedding-2 - handed 20 inputs it returns ONE embedding and silently
  # drops the other 19 (parse_embeddings' count guard turns that into an error
  # rather than a misalignment). One request per text against the key's 100 rpm
  # would put a full corpus pass near 180 hours.
  #
  # It is NOT about task types, despite an earlier comment here saying so.
  # Measured on both routes: gemini-embedding-2 returns cosine 1.000000 between
  # RETRIEVAL_QUERY and RETRIEVAL_DOCUMENT, i.e. it IGNORES task type everywhere
  # (the pass-through does validate the field - a bogus value 400s - it just has
  # no effect for this model). So gemini-embedding-2 vectors are SYMMETRIC, and
  # the task type we send it is inert. It is still sent because the code path is
  # shared with models that do honour it: text-multilingual-embedding-002 (cos
  # 0.863) and gemini-embedding-001 (cos 0.844).
  #
  # Config is read from ENV so the value is identical in the Rails and Traject
  # processes:
  #   SEMANTIC_SEARCH_EMBEDDING_API_KEY  - required; the gateway key
  #   SEMANTIC_SEARCH_EMBEDDING_API_BASE - override the gateway base (optional);
  #                                        applies to BOTH transports
  #   SEMANTIC_SEARCH_EMBED_BATCH_SIZE   - inputs per request (optional)
  #
  # Max input is 8,192 tokens, so we clamp very long inputs by characters.
  class EmbeddingService
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
    # batchEmbedContents caps requests lower than the OpenAI route does.
    DEFAULT_GEMINI_BATCH_SIZE = 50
    # Pass-through prefix, appended to the shared gateway base.
    GEMINI_PATH = '/gemini/v1beta/models'

    DEFAULT_ENDPOINT = 'https://dlss-aigateway-prod.stanford.edu'
    DEFAULT_TIMEOUT = 30

    # Clamp inputs by characters to stay under the model's input-token limit
    # (gemini-embedding-2 is 8,192; the Vertex text-embedding models are ~2,048).
    # Override with SEMANTIC_SEARCH_MAX_INPUT_CHARS when switching models.
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
      Integer(ENV.fetch('SEMANTIC_SEARCH_EMBED_BATCH_SIZE',
                        gemini_native? ? DEFAULT_GEMINI_BATCH_SIZE : DEFAULT_BATCH_SIZE))
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
    def token_batches(texts)
      cap = batch_size
      budget = token_budget
      batches = []
      current = []
      current_tokens = 0
      texts.each do |text|
        est = estimated_tokens(text)
        if !current.empty? && (current.size >= cap || current_tokens + est > budget)
          batches << current
          current = []
          current_tokens = 0
        end
        current << text
        current_tokens += est
      end
      batches << current unless current.empty?
      batches
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
    # an instant retry that keeps the rate-limit window from ever draining - a
    # 429 death-spiral that makes no progress while pegging CPU on retries.
    def wait_before_retry(error, attempt)
      wait = [error.retry_after.to_i, backoff(attempt)].max
      logger&.warn("[SemanticSearch] rate limited (429); retry #{attempt}/#{max_retries} in #{wait}s")
      sleep(wait)
    end

    def send_embed_request(texts, task_type)
      response = post_transport(texts, task_type)
      raise rate_limit_error(response) if response.status == 429
      raise ApiError, "Embedding gateway returned #{response.status}: #{response.body}" unless response.success?

      parse_transport(response.body, texts.size)
    end

    def post_transport(texts, task_type)
      return post_gemini(texts, task_type) if gemini_native?

      post_embed(embed_body(texts, task_type))
    end

    def parse_transport(body, expected)
      return parse_gemini_embeddings(body, expected) if gemini_native?

      parse_embeddings(body, expected)
    end

    def gemini_native?
      SemanticSearch.gemini_native?
    end

    # OpenAI-style /embeddings request body. task_type is a non-OpenAI param the
    # gateway forwards to Vertex.
    def embed_body(texts, task_type)
      { model: SemanticSearch.embedding_model, input: texts.map { |t| clamp(t) },
        encoding_format: 'float', task_type: task_type }
    end

    # Native Gemini batchEmbedContents. Unlike the OpenAI route this takes a real
    # outputDimensionality, so we ask for DIMENSIONS rather than truncating to it,
    # and it authenticates with `?key=` rather than a bearer header.
    def post_gemini(texts, task_type)
      model = SemanticSearch.embedding_model
      body = { requests: texts.map { |text| gemini_content_request(model, text, task_type) } }
      connection.post("#{GEMINI_PATH}/#{model}:batchEmbedContents") do |req|
        req.params['key'] = api_key
        req.headers['Content-Type'] = 'application/json'
        req.body = JSON.generate(body)
      end
    end

    def gemini_content_request(model, text, task_type)
      { model: "models/#{model}",
        content: { parts: [{ text: clamp(text) }] },
        taskType: task_type,
        outputDimensionality: DIMENSIONS }
    end

    # batchEmbedContents answers {"embeddings":[{"values":[...]}]} in request
    # order - no index to sort by, so alignment relies on that order and on the
    # count guard below.
    def parse_gemini_embeddings(raw, expected)
      parsed = raw.is_a?(String) ? JSON.parse(raw.dup.force_encoding('UTF-8')) : raw
      data = parsed.fetch('embeddings')
      raise ApiError, "expected #{expected} embeddings, got #{data.size}" unless data.size == expected

      data.map { |row| to_dimensions(row.fetch('values')) }
    rescue KeyError, JSON::ParserError => e
      raise ApiError, "Unexpected embedding response shape: #{e.message}"
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
    # native output size. On the gemini transport the response is already
    # DIMENSIONS wide (outputDimensionality), making the truncation a no-op - but
    # the renormalization still matters, since Gemini's MRL truncation below its
    # native width returns non-unit vectors (Google's guidance).
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
