# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SemanticSearch::EmbeddingService do
  subject(:service) { described_class.new }

  let(:embed_url) { 'https://gateway.test/embeddings' }

  around do |example|
    keys = %w[SEMANTIC_SEARCH_EMBEDDING_API_KEY SEMANTIC_SEARCH_EMBEDDING_API_BASE
              SEMANTIC_SEARCH_EMBED_BATCH_SIZE SEMANTIC_SEARCH_EMBED_MAX_RETRIES
              SEMANTIC_SEARCH_EMBEDDING_MODEL
              SEMANTIC_SEARCH_EMBED_TOKEN_BUDGET SEMANTIC_SEARCH_CHARS_PER_TOKEN]
    original = ENV.to_h.slice(*keys)
    ENV['SEMANTIC_SEARCH_EMBEDDING_API_KEY'] = 'test-key'
    ENV['SEMANTIC_SEARCH_EMBEDDING_API_BASE'] = 'https://gateway.test'
    ENV.delete('SEMANTIC_SEARCH_EMBED_BATCH_SIZE')
    ENV.delete('SEMANTIC_SEARCH_EMBED_MAX_RETRIES') # retries off by default
    # Set explicitly rather than relying on the default, so these specs don't
    # quietly change meaning if the default model changes.
    ENV['SEMANTIC_SEARCH_EMBEDDING_MODEL'] = 'text-multilingual-embedding-002'
    example.run
    keys.each { |k| ENV.delete(k) }
    original.each { |k, v| ENV[k] = v }
  end

  # Build an OpenAI-style embeddings response body from an array of vectors.
  def response_body(vectors)
    { data: vectors.each_with_index.map { |v, i| { index: i, embedding: v } } }.to_json
  end

  def one_hot(pos, len = 768)
    Array.new(len, 0.0).tap { |a| a[pos] = 1.0 }
  end

  describe '#embed' do
    it 'posts an OpenAI-style request with bearer auth and returns a 768-dim unit vector' do
      stub = stub_request(:post, embed_url)
             .with(headers: { 'Authorization' => 'Bearer test-key' }) do |req|
               body = JSON.parse(req.body)
               body['model'] == 'text-multilingual-embedding-002' &&
                 body['input'] == ['ships'] &&
                 body['encoding_format'] == 'float'
             end
             .to_return(status: 200, body: response_body([Array.new(768, 0.1)]))

      result = service.embed('ships')
      expect(result.length).to eq(768)
      expect(result.sum { |x| x * x }).to be_within(1e-6).of(1.0) # normalized
      expect(stub).to have_been_requested
    end
  end

  describe 'model + task_type configuration' do
    def captured_body
      body = nil
      stub_request(:post, embed_url).with do |req|
        body = JSON.parse(req.body)
        true
      end
                                    .to_return(status: 200, body: response_body([Array.new(768, 0.1)]))
      service.embed('ships', task_type: SemanticSearch::EmbeddingService::QUERY_TASK_TYPE)
      body
    end

    it 'uses SEMANTIC_SEARCH_EMBEDDING_MODEL when set' do
      ENV['SEMANTIC_SEARCH_EMBEDDING_MODEL'] = 'text-embedding-005'
      expect(captured_body['model']).to eq('text-embedding-005')
    end

    it 'sends task_type on the OpenAI transport' do
      expect(captured_body['task_type']).to eq('RETRIEVAL_QUERY')
    end

    it 'sends task_type for text-embedding-005' do
      ENV['SEMANTIC_SEARCH_EMBEDDING_MODEL'] = 'text-embedding-005'
      expect(captured_body['task_type']).to eq('RETRIEVAL_QUERY')
    end
  end

  describe '#embed_batch' do
    it 'returns one vector per input, re-ordered by the response index' do
      # respond out of order to prove we sort by `index`
      body = { data: [{ index: 1, embedding: one_hot(1) }, { index: 0, embedding: one_hot(0) }] }.to_json
      stub_request(:post, embed_url).to_return(status: 200, body: body)

      vecs = service.embed_batch(%w[a b])
      expect(vecs.length).to eq(2)
      expect(vecs[0][0]).to eq(1.0) # input a -> index 0
      expect(vecs[1][1]).to eq(1.0) # input b -> index 1
    end

    it 'returns [] for empty input without calling the gateway' do
      expect(service.embed_batch([])).to eq([])
      expect(a_request(:post, embed_url)).not_to have_been_made
    end

    it 'splits a batch into multiple requests to respect the per-request token budget' do
      ENV['SEMANTIC_SEARCH_CHARS_PER_TOKEN'] = '1' # 1 token per char, for easy math
      ENV['SEMANTIC_SEARCH_EMBED_TOKEN_BUDGET'] = '10'
      inputs_seen = []
      stub_request(:post, embed_url)
        .to_return do |req|
          input = JSON.parse(req.body)['input']
          inputs_seen << input
          { status: 200, body: response_body(input.map { Array.new(768, 0.1) }) }
        end

      # 4-char inputs = 4 tokens each; budget 10 -> [aaaa,bbbb]=8, then [cccc]=4
      service.embed_batch(%w[aaaa bbbb cccc])
      expect(inputs_seen).to eq([%w[aaaa bbbb], %w[cccc]])
    end
  end

  describe 'dimensionality (client-side Matryoshka handling)' do
    it 'truncates a larger native vector to 768 and normalizes' do
      stub_request(:post, embed_url).to_return(status: 200, body: response_body([Array.new(3072, 0.05)]))
      result = service.embed('x')
      expect(result.length).to eq(768)
      expect(result.sum { |v| v * v }).to be_within(1e-6).of(1.0)
    end

    it 'raises when the gateway returns fewer than 768 dims' do
      stub_request(:post, embed_url).to_return(status: 200, body: response_body([Array.new(256, 0.1)]))
      expect { service.embed('x') }.to raise_error(described_class::ApiError, /dims/)
    end
  end

  describe 'error handling' do
    it 'raises ConfigurationError when the API key is not configured' do
      ENV.delete('SEMANTIC_SEARCH_EMBEDDING_API_KEY')
      expect { service.embed('x') }.to raise_error(described_class::ConfigurationError)
    end

    it 'raises ApiError on a non-success HTTP status' do
      stub_request(:post, embed_url).to_return(status: 500, body: 'boom')
      expect { service.embed('x') }.to raise_error(described_class::ApiError, /500/)
    end

    it 'raises ApiError on an unexpected response shape' do
      stub_request(:post, embed_url).to_return(status: 200, body: { nope: true }.to_json)
      expect { service.embed('x') }.to raise_error(described_class::ApiError)
    end

    it 'raises ApiError on a transport failure' do
      stub_request(:post, embed_url).to_timeout
      expect { service.embed('x') }.to raise_error(described_class::ApiError)
    end

    it 'raises ApiError on a partial response (fewer embeddings than inputs)' do
      stub_request(:post, embed_url).to_return(status: 200, body: response_body([one_hot(0)]))
      expect { service.embed_batch(%w[a b]) }.to raise_error(described_class::ApiError, /expected 2/)
    end
  end

  # These backoff tests stub and observe the retry sleep (a side-effect-only
  # Kernel method), which is safe to stub on the subject.
  # rubocop:disable RSpec/SubjectStub
  describe 'rate limiting (HTTP 429)' do
    before { allow(service).to receive(:sleep) } # don't actually wait in tests

    it 'raises RateLimitError (an ApiError) and fails fast when retries are off' do
      stub_request(:post, embed_url).to_return(status: 429, body: '{"error":{"code":"429"}}')
      expect { service.embed('x') }.to raise_error(described_class::RateLimitError)
      expect(described_class::RateLimitError.ancestors).to include(described_class::ApiError)
    end

    it 'retries a 429 and succeeds when retries are enabled' do
      ENV['SEMANTIC_SEARCH_EMBED_MAX_RETRIES'] = '2'
      stub = stub_request(:post, embed_url)
             .to_return({ status: 429, headers: { 'Retry-After' => '0' }, body: '{}' },
                        { status: 200, body: response_body([Array.new(768, 0.1)]) })

      expect(service.embed('x').length).to eq(768)
      expect(stub).to have_been_requested.twice
    end

    it 'does not let a Retry-After of 0 disable exponential backoff (429 death-spiral guard)' do
      ENV['SEMANTIC_SEARCH_EMBED_MAX_RETRIES'] = '2'
      stub_request(:post, embed_url)
        .to_return({ status: 429, headers: { 'Retry-After' => '0' }, body: '{}' },
                   { status: 200, body: response_body([Array.new(768, 0.1)]) })

      service.embed('x')

      expect(service).to have_received(:sleep).with(2) # backoff(1), not the server's 0
    end

    it 'honors a Retry-After longer than the backoff' do
      ENV['SEMANTIC_SEARCH_EMBED_MAX_RETRIES'] = '2'
      stub_request(:post, embed_url)
        .to_return({ status: 429, headers: { 'Retry-After' => '30' }, body: '{}' },
                   { status: 200, body: response_body([Array.new(768, 0.1)]) })

      service.embed('x')

      expect(service).to have_received(:sleep).with(30)
    end
  end
  # rubocop:enable RSpec/SubjectStub
end
