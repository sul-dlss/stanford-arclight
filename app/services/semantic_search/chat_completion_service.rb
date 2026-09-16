# frozen_string_literal: true

require 'faraday'
require 'json'

module SemanticSearch
  # Minimal client for chat completions via the same Stanford LiteLLM AI
  # gateway used by EmbeddingService (https://dlss-aigateway-prod.stanford.edu).
  # Reuses the SAME env-configured credentials - this is one gateway that
  # serves both embedding and chat models.
  #
  # Deliberately thin (no batching, no retries): callers of this class are
  # best-effort UI panels that should render nothing on failure rather than
  # hold up a page, unlike the embedding path which retries through rate
  # limits during bulk indexing.
  class ChatCompletionService
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class ApiError < Error; end

    def initialize(timeout: 8)
      @timeout = timeout
    end

    # @param messages [Array<Hash>] OpenAI-style [{role:, content:}, ...]
    # @param model [String]
    # @return [String] the completion text
    def complete(messages, model:, max_tokens: 400, temperature: 0.2)
      body = { model: model, messages: messages, max_tokens: max_tokens, temperature: temperature }
      response = post_chat(body)
      raise ApiError, "Chat completion gateway returned #{response.status}: #{response.body}" unless response.success?

      parse_content(response.body)
    rescue Faraday::Error => e
      raise ApiError, "Chat completion request failed: #{e.class}: #{e.message}"
    end

    private

    attr_reader :timeout

    def post_chat(body)
      connection.post('/chat/completions') do |req|
        req.headers['Authorization'] = "Bearer #{api_key}"
        req.headers['Content-Type'] = 'application/json'
        req.body = JSON.generate(body)
      end
    end

    def parse_content(raw)
      parsed = raw.is_a?(String) ? JSON.parse(raw) : raw
      parsed.dig('choices', 0, 'message', 'content').to_s
    rescue JSON::ParserError => e
      raise ApiError, "Unexpected chat completion response shape: #{e.message}"
    end

    def connection
      @connection ||= Faraday.new(url: api_base) do |f|
        f.options.timeout = timeout
        f.options.open_timeout = timeout
        f.adapter Faraday.default_adapter
      end
    end

    def api_base
      ENV.fetch('SEMANTIC_SEARCH_EMBEDDING_API_BASE', 'https://dlss-aigateway-prod.stanford.edu')
    end

    def api_key
      key = ENV.fetch('SEMANTIC_SEARCH_EMBEDDING_API_KEY', nil)
      return key unless key.to_s.empty?

      raise ConfigurationError, 'SEMANTIC_SEARCH_EMBEDDING_API_KEY is not set'
    end
  end
end
