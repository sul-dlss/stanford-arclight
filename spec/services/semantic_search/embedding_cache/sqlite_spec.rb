# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe SemanticSearch::EmbeddingCache::Sqlite do
  around do |example|
    Dir.mktmpdir do |dir|
      @path = File.join(dir, 'embeddings.sqlite')
      example.run
    end
  end

  attr_reader :path

  it 'round-trips a vector by content hash (to float32 precision)' do
    cache = described_class.new(path, writable: true)
    cache.store('some text', [0.1, -0.2, 0.3])

    expect(cache.fetch('some text'))
      .to match([be_within(1e-6).of(0.1), be_within(1e-6).of(-0.2), be_within(1e-6).of(0.3)])
    expect(cache.fetch('different text')).to be_nil
    cache.close
  end

  it 'keeps the first write (INSERT OR IGNORE) so concurrent generators do not clobber' do
    cache = described_class.new(path, writable: true)
    cache.store('t', [1.0])
    cache.store('t', [9.0])
    expect(cache.fetch('t').first).to be_within(1e-6).of(1.0)
    expect(cache.size).to eq(1)
    cache.close
  end

  context 'when read-only (serving) over an existing file' do
    subject(:cache) { described_class.new(path, writable: false) }

    before do
      writer = described_class.new(path, writable: true)
      writer.store('doc', [0.5, 0.5])
      writer.close
    end

    after { cache.close }

    it 'reads an existing immutable file' do
      expect(cache.writable?).to be false
      expect(cache.fetch('doc')).to match([be_within(1e-6).of(0.5), be_within(1e-6).of(0.5)])
    end

    it 'does not write' do
      expect(cache.store('new', [1.0])).to be_nil
      expect(cache.fetch('new')).to be_nil
    end
  end
end
