# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SemanticSearch::ChatCompletionService do
  let(:messages) { [{ role: 'user', content: 'Hello' }] }
  let(:url) { 'https://gateway.example.com/chat/completions' }
  let(:sent_bodies) { [] }

  before do
    stub_const('ENV', ENV.to_h.merge('SEMANTIC_SEARCH_EMBEDDING_API_BASE' => 'https://gateway.example.com',
                                     'SEMANTIC_SEARCH_EMBEDDING_API_KEY' => 'test-key'))
    stub_request(:post, url).to_return do |request|
      sent_bodies << JSON.parse(request.body)
      { status: 200, body: { choices: [{ message: { content: 'Hi' } }] }.to_json }
    end
  end

  it 'leaves out temperature and reasoning_effort by default' do
    expect(described_class.new.complete(messages, model: 'claude-haiku')).to eq 'Hi'
    expect(sent_bodies.first.keys).to contain_exactly('model', 'messages', 'max_tokens')
  end

  it 'sends temperature and reasoning_effort when given' do
    described_class.new.complete(messages, model: 'claude-haiku', temperature: 1, reasoning_effort: 'low')
    expect(sent_bodies.first).to include('temperature' => 1, 'reasoning_effort' => 'low')
  end
end
