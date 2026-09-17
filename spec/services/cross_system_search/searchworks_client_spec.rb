# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CrossSystemSearch::SearchworksClient do
  subject(:client) { described_class.new(timeout: 1) }

  describe '#search' do
    it 'returns the total and docs on a successful response' do
      stub_request(:get, 'https://searchworks.stanford.edu/catalog.json')
        .with(query: { q: 'jazz', rows: '3' })
        .to_return(status: 200, body: {
          response: { pages: { total_count: 1204 }, docs: [{ 'id' => '6418989', 'title_display' => 'Jazz' }] }
        }.to_json)

      result = client.search('jazz', rows: 3)

      expect(result.total).to eq 1204
      expect(result.docs).to eq [{ 'id' => '6418989', 'title_display' => 'Jazz' }]
    end

    it 'returns nil on a non-success response' do
      stub_request(:get, %r{https://searchworks\.stanford\.edu/catalog\.json}).to_return(status: 500)

      expect(client.search('jazz')).to be_nil
    end

    it 'returns nil on a connection failure' do
      stub_request(:get, %r{https://searchworks\.stanford\.edu/catalog\.json}).to_raise(Faraday::ConnectionFailed)

      expect(client.search('jazz')).to be_nil
    end

    it 'returns nil on an unparseable body' do
      stub_request(:get, %r{https://searchworks\.stanford\.edu/catalog\.json}).to_return(status: 200, body: 'not json')

      expect(client.search('jazz')).to be_nil
    end
  end

  describe '.doc_view' do
    it 'is nil for a nil doc' do
      expect(described_class.doc_view(nil)).to be_nil
    end

    it 'builds a title and a /view/{id} url (not /catalog/{id}, which 404s)' do
      expect(described_class.doc_view({ 'id' => '6418989', 'title_display' => 'Jazz' }))
        .to eq(title: 'Jazz', url: 'https://searchworks.stanford.edu/view/6418989')
    end

    it 'falls back to title_full_display when title_display is missing' do
      doc = { 'id' => '123', 'title_full_display' => 'Jazz [sound recording] / Cleo Laine.' }

      expect(described_class.doc_view(doc)[:title]).to eq 'Jazz [sound recording] / Cleo Laine.'
    end
  end

  describe '.search_url' do
    it 'builds the human-facing search results page for the query' do
      expect(described_class.search_url('jazz')).to eq 'https://searchworks.stanford.edu/catalog?q=jazz'
    end
  end

  describe '.describe_for_prompt' do
    it 'is nil for a nil doc' do
      expect(described_class.describe_for_prompt(nil)).to be_nil
    end

    it 'includes the real format when present' do
      doc = { 'id' => '1', 'title_display' => 'Jazz', 'format_main_ssim' => ['Music recording'] }

      expect(described_class.describe_for_prompt(doc)).to eq 'Jazz (Music recording)'
    end

    it 'falls back to just the title when no format is present' do
      doc = { 'id' => '1', 'title_display' => 'Jazz' }

      expect(described_class.describe_for_prompt(doc)).to eq 'Jazz'
    end
  end
end
