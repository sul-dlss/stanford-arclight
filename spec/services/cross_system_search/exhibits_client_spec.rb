# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CrossSystemSearch::ExhibitsClient do
  subject(:client) { described_class.new(timeout: 1) }

  describe '#search' do
    it 'returns the total_count and docs on a successful response' do
      stub_request(:get, 'https://exhibits.stanford.edu/search.json')
        .with(query: { q: 'jazz', search_field: 'default', per_page: '3' })
        .to_return(status: 200, body: {
          meta: { pages: { total_count: 5454 } },
          data: [{ 'id' => 'vr492jd7028', 'type' => 'file',
                   'attributes' => { 'title' => 'Jazz Casual, Turk Murphy Jazz Band' },
                   'links' => { 'self' => 'https://exhibits.stanford.edu/catalog/vr492jd7028' } }]
        }.to_json)

      result = client.search('jazz', rows: 3)

      expect(result.total).to eq 5454
      expect(result.docs.first['id']).to eq 'vr492jd7028'
    end

    it 'returns nil on a non-success response' do
      stub_request(:get, %r{https://exhibits\.stanford\.edu/search\.json}).to_return(status: 500)

      expect(client.search('jazz')).to be_nil
    end

    it 'returns nil on a connection failure' do
      stub_request(:get, %r{https://exhibits\.stanford\.edu/search\.json}).to_raise(Faraday::ConnectionFailed)

      expect(client.search('jazz')).to be_nil
    end
  end

  describe '.doc_view' do
    it 'is nil for a nil doc' do
      expect(described_class.doc_view(nil)).to be_nil
    end

    it 'builds a title and the exhibit-scoped url, NOT the bare links.self (which redirects to an error page)' do
      doc = { 'id' => 'vr492jd7028',
              'attributes' => {
                'title' => 'Jazz Casual, Turk Murphy Jazz Band',
                'spotlight_exhibit_slugs_ssim' => {
                  'attributes' => {
                    'value' => '<a href="/sftjf/catalog/vr492jd7028">San Francisco Traditional Jazz Foundation</a> '
                  }
                }
              },
              'links' => { 'self' => 'https://exhibits.stanford.edu/catalog/vr492jd7028' } }

      expect(described_class.doc_view(doc)).to eq(
        title: 'Jazz Casual, Turk Murphy Jazz Band',
        url: 'https://exhibits.stanford.edu/sftjf/catalog/vr492jd7028'
      )
    end

    it 'falls back to the id when no title attribute is present' do
      slug_html = '<a href="/sftjf/catalog/vr492jd7028">x</a>'
      doc = { 'id' => 'vr492jd7028',
              'attributes' => { 'spotlight_exhibit_slugs_ssim' => { 'attributes' => { 'value' => slug_html } } } }

      expect(described_class.doc_view(doc)[:title]).to eq 'vr492jd7028'
    end

    it 'is nil (not a dead-link hash) when the exhibit-scoped anchor is missing' do
      doc = { 'id' => 'vr492jd7028', 'attributes' => { 'title' => 'Jazz Casual' }, 'links' => {} }

      expect(described_class.doc_view(doc)).to be_nil
    end
  end

  describe '.search_url' do
    it 'builds the human-facing (non-.json) search results page for the query' do
      expect(described_class.search_url('jazz')).to eq 'https://exhibits.stanford.edu/search?q=jazz&search_field=default'
    end
  end

  describe '.describe_for_prompt' do
    it 'is nil for a nil doc' do
      expect(described_class.describe_for_prompt(nil)).to be_nil
    end

    it 'includes the real JSON:API resource type when present' do
      doc = { 'id' => 'vr492jd7028', 'type' => 'image', 'attributes' => { 'title' => 'Jazz Casual' } }

      expect(described_class.describe_for_prompt(doc)).to eq 'Jazz Casual (image)'
    end

    it 'falls back to just the title when no type is present' do
      doc = { 'id' => 'vr492jd7028', 'attributes' => { 'title' => 'Jazz Casual' } }

      expect(described_class.describe_for_prompt(doc)).to eq 'Jazz Casual'
    end
  end
end
