# frozen_string_literal: true

# Minimal client for the NATIVE Gemini embeddings API exposed via the Stanford
# LiteLLM gateway's `/gemini` pass-through (generativelanguage, not Vertex).
# Unlike the OpenAI-compatible route, this one supports real multi-input
# batching (batchEmbedContents), a per-request taskType, and outputDimensionality
# - so we can ask for 768 dims directly to match the existing index.
#
# Scratchpad-only: used by the gemini-vs-002 A/B harness. If gemini wins we
# promote a hardened version into app/services (a proper EmbeddingService
# adapter). Auth is the same gateway key as the OpenAI-compat path, passed as a
# ?key= query param here (native Gemini style).
#
#   curl ".../gemini/v1beta/models/gemini-embedding-2:batchEmbedContents?key=K"
#     -d '{"requests":[{"model":"models/gemini-embedding-2",
#                       "content":{"parts":[{"text":"..."}]},
#                       "taskType":"RETRIEVAL_DOCUMENT",
#                       "outputDimensionality":768}]}'
require 'faraday'
require 'json'

class GeminiEmbedder
  DOCUMENT_TASK_TYPE = 'RETRIEVAL_DOCUMENT'
  QUERY_TASK_TYPE = 'RETRIEVAL_QUERY'
  DIMS = 768
  MAX_INPUT_CHARS = 30_000

  class ApiError < StandardError; end

  def initialize(key: ENV.fetch('SEMANTIC_SEARCH_EMBEDDING_API_KEY'),
                 base: ENV.fetch('SEMANTIC_SEARCH_GEMINI_API_BASE',
                                 'https://dlss-aigateway-prod.stanford.edu/gemini/v1beta'),
                 model: ENV.fetch('SEMANTIC_SEARCH_GEMINI_MODEL', 'gemini-embedding-2'),
                 batch_size: Integer(ENV.fetch('SEMANTIC_SEARCH_GEMINI_BATCH_SIZE', 50)),
                 timeout: 60)
    @key = key
    @model = model
    @batch_size = batch_size
    @conn = Faraday.new(url: base) { |f| f.options.timeout = timeout }
  end

  # @param texts [Array<String>]
  # @param task_type [String] DOCUMENT_TASK_TYPE / QUERY_TASK_TYPE
  # @return [Array<Array<Float>>] one unit-normalized 768-dim vector per input
  def embed_batch(texts, task_type: DOCUMENT_TASK_TYPE)
    Array(texts).each_slice(@batch_size).flat_map { |slice| request(slice, task_type) }
  end

  def embed(text, task_type: QUERY_TASK_TYPE)
    embed_batch([text], task_type: task_type).first
  end

  private

  def request(slice, task_type, attempt: 0)
    body = { requests: slice.map { |t| content_request(t, task_type) } }
    resp = @conn.post("models/#{@model}:batchEmbedContents") do |r|
      r.params['key'] = @key
      r.headers['Content-Type'] = 'application/json'
      r.body = JSON.generate(body)
    end
    return parse(resp.body) if resp.success?

    # basic 429/5xx backoff
    if [429, 500, 502, 503].include?(resp.status) && attempt < 5
      sleep(2**attempt)
      return request(slice, task_type, attempt: attempt + 1)
    end
    raise ApiError, "gemini #{resp.status}: #{resp.body.to_s[0, 300]}"
  end

  def content_request(text, task_type)
    { model: "models/#{@model}",
      content: { parts: [{ text: text.to_s[0, MAX_INPUT_CHARS] }] },
      taskType: task_type,
      outputDimensionality: DIMS }
  end

  def parse(raw)
    JSON.parse(raw.force_encoding('UTF-8')).fetch('embeddings').map { |e| normalize(e.fetch('values')) }
  end

  # L2-normalize: Gemini's MRL truncation to < native dims returns non-unit
  # vectors, so renormalize before cosine (Google's guidance).
  def normalize(vec)
    norm = Math.sqrt(vec.sum { |x| x * x })
    norm.zero? ? vec : vec.map { |x| x / norm }
  end
end
