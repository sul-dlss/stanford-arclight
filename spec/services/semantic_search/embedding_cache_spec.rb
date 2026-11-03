# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe SemanticSearch::EmbeddingCache do
  around do |example|
    Dir.mktmpdir do |dir|
      @path = File.join(dir, 'e.sqlite')
      example.run
    end
  end

  attr_reader :path

  describe '.build' do
    it 'returns nil when no path is configured' do
      expect(described_class.build(path: nil)).to be_nil
      expect(described_class.build(path: '')).to be_nil
    end

    it 'creates a writable cache in write mode' do
      cache = described_class.build(path:, writable: true)
      expect(cache).to be_a(described_class::Sqlite).and(have_attributes(writable?: true))
      cache.close
    end

    it 'returns nil and warns when a read-only cache file is missing' do
      logger = instance_double(Logger, warn: nil)
      expect(described_class.build(path:, writable: false, logger:)).to be_nil
      expect(logger).to have_received(:warn).with(/not found/)
    end

    it 'opens an existing file read-only' do
      described_class.build(path:, writable: true).close
      cache = described_class.build(path:, writable: false)
      expect(cache).to be_a(described_class::Sqlite).and(have_attributes(writable?: false))
      cache.close
    end
  end
end
