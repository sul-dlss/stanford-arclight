# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe SemanticSearch::CacheGenerator do
  subject(:generator) do
    described_class.new(cache:, embedding_service: service, batch_size: 3, logger:)
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @path = File.join(dir, 'c.sqlite')
      example.run
    end
  end

  attr_reader :path

  let(:cache) { SemanticSearch::EmbeddingCache::Sqlite.new(path, writable: true) }
  let(:service) { instance_double(SemanticSearch::EmbeddingService) }
  let(:logger) { instance_double(Logger, info: nil, warn: nil) }

  after { cache.close }

  it 'batch-embeds buffered texts and stores them, positionally aligned' do
    allow(service).to receive(:embed_batch) { |texts, **| texts.map { |t| [t.length.to_f] } }

    generator.add('aa')
    generator.add('bbb')
    generator.flush

    expect(cache.fetch('aa')).to match([be_within(1e-6).of(2.0)])
    expect(cache.fetch('bbb')).to match([be_within(1e-6).of(3.0)])
    expect(service).to have_received(:embed_batch).once
  end

  it 'auto-flushes when the buffer reaches batch_size' do
    allow(service).to receive(:embed_batch) { |texts, **| texts.map { [0.1] } }

    3.times { |i| generator.add("t#{i}") } # batch_size = 3

    expect(service).to have_received(:embed_batch).once
    expect(generator.stats[:embedded]).to eq(3)
  end

  it 'de-duplicates identical texts within a batch' do
    allow(service).to receive(:embed_batch) { |texts, **| texts.map { [0.1] } }

    generator.add('dup')
    generator.add('dup')
    generator.flush

    expect(service).to have_received(:embed_batch)
      .with(['dup'], task_type: SemanticSearch::EmbeddingService::DOCUMENT_TASK_TYPE)
    expect(generator.stats).to include(seen: 2, embedded: 1)
  end

  it 'skips texts already in the cache (resumable) without re-embedding' do
    allow(service).to receive(:embed_batch)
    cache.store('done', [9.0])

    generator.add('done')
    generator.flush

    expect(generator.stats[:skipped]).to eq(1)
    expect(service).not_to have_received(:embed_batch)
  end

  it 'logs and drops a batch that fails to embed, leaving it uncached for a re-run' do
    allow(service).to receive(:embed_batch).and_raise(SemanticSearch::EmbeddingService::ApiError, 'boom')

    generator.add('x')
    generator.flush

    expect(cache.fetch('x')).to be_nil
    expect(generator.stats[:failed]).to eq(1)
    expect(logger).to have_received(:warn).with(/failed/)
  end

  it 'ignores nil/empty text' do
    generator.add(nil)
    generator.add('')
    generator.flush
    expect(generator.stats[:seen]).to eq(0)
  end

  # The whole point of the threaded generation pass: the gateway round-trip is
  # the cost, so it must NOT be serialized behind the buffer's mutex.
  describe 'concurrency' do
    it 'does not hold the lock across the embedding call' do
      inside = 0
      overlapped = false
      barrier = Mutex.new
      allow(service).to receive(:embed_batch) do |texts, **|
        barrier.synchronize { inside += 1 }
        overlapped = true if inside > 1
        sleep 0.05 # hold the "request" open long enough for a peer to enter
        barrier.synchronize { inside -= 1 }
        texts.map { [0.1] }
      end

      # batch_size is 3, so each thread's 3rd add triggers its own flush.
      threads = Array.new(4) { |t| Thread.new { 3.times { |i| generator.add("t#{t}-#{i}") } } }
      threads.each(&:join)

      expect(overlapped).to be(true), 'embedding calls were serialized - the mutex is held across the request'
    end

    it 'stores every vector exactly once under concurrent adds' do
      allow(service).to receive(:embed_batch) { |texts, **| texts.map { |t| [t.length.to_f] } }

      texts = Array.new(60) { |i| "text-number-#{i}" }
      texts.each_slice(15).map { |slice| Thread.new { slice.each { |t| generator.add(t) } } }.each(&:join)
      generator.flush

      expect(generator.stats).to include(seen: 60, embedded: 60, failed: 0)
      # Each text's vector encodes its own length, so a crossed response would show up here.
      texts.each { |t| expect(cache.fetch(t)&.first).to be_within(1e-6).of(t.length.to_f) }
    end

    it 'confines a failing batch to its own texts when other threads succeed' do
      allow(service).to receive(:embed_batch) do |texts, **|
        raise SemanticSearch::EmbeddingService::ApiError, 'boom' if texts.any? { |t| t.start_with?('bad') }

        texts.map { [0.1] }
      end

      good = Array.new(3) { |i| "good-#{i}" }
      bad = Array.new(3) { |i| "bad-#{i}" }
      [good, bad].map { |slice| Thread.new { slice.each { |t| generator.add(t) } } }.each(&:join)
      generator.flush

      expect(generator.stats).to include(embedded: 3, failed: 3)
      expect(good.map { |t| cache.fetch(t) }).to all(be_present)
      expect(bad.map { |t| cache.fetch(t) }).to all(be_nil)
    end
  end
end
