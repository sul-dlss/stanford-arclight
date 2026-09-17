# frozen_string_literal: true

require 'faraday'
require 'json'
require 'uri'
require 'nokogiri'

module CrossSystemSearch
  # Thin client for exhibits.stanford.edu's public `search.json` endpoint - a
  # unified, item-level, cross-exhibit search (JSON:API shaped), distinct from
  # the spotlight.stanford.edu browse UI which has no such API. No auth;
  # deliberately best-effort like SearchworksClient.
  class ExhibitsClient
    BASE_URL = 'https://exhibits.stanford.edu'

    Result = Struct.new(:total, :docs, keyword_init: true)

    def initialize(timeout: 5)
      @timeout = timeout
    end

    # @return [Result, nil] nil on any request/parse failure
    def search(query, rows: 3)
      response = connection.get('/search.json', { q: query, search_field: 'default', per_page: rows })
      return nil unless response.success?

      body = JSON.parse(response.body)
      Result.new(total: body.dig('meta', 'pages', 'total_count').to_i, docs: Array(body['data']))
    rescue Faraday::Error, JSON::ParserError
      nil
    end

    # @param doc [Hash, nil] a single result from Result#docs (JSON:API resource)
    # @return [Hash, nil] { title:, url: } - nil (not a partial/dead-link hash)
    #   when no exhibit-scoped link can be recovered
    def self.doc_view(doc)
      return nil unless doc

      attributes = doc['attributes'] || {}
      url = exhibit_scoped_url(attributes)
      return nil unless url

      { title: attributes['title'].presence || doc['id'], url: url }
    end

    # `links.self` in the response (bare `/catalog/{id}`) redirects to an
    # error page - items only resolve under their owning exhibit's path (e.g.
    # `/su-photos/catalog/{id}`), which is only recoverable from the anchor
    # tag embedded in this display field. Confirmed by clicking both live.
    def self.exhibit_scoped_url(attributes)
      html = attributes.dig('spotlight_exhibit_slugs_ssim', 'attributes', 'value')
      return nil if html.blank?

      href = Nokogiri::HTML5.fragment(html).at_css('a')&.[]('href')
      href ? "#{BASE_URL}#{href}" : nil
    end

    # @return [String] the human-facing (not .json) search results page for this query
    def self.search_url(query)
      "#{BASE_URL}/search?#{URI.encode_www_form(q: query, search_field: 'default')}"
    end

    # Grounding text for the LLM prompt only (never rendered) - real title +
    # JSON:API resource type (e.g. "image", "file"), so a "kinds of results"
    # summary can be based on actual item types rather than guessed.
    def self.describe_for_prompt(doc)
      return nil unless doc

      title = doc.dig('attributes', 'title').presence || doc['id']
      doc['type'].present? ? "#{title} (#{doc['type']})" : title.to_s
    end

    private

    attr_reader :timeout

    def connection
      @connection ||= Faraday.new(url: BASE_URL) do |f|
        f.options.timeout = timeout
        f.options.open_timeout = timeout
        f.adapter Faraday.default_adapter
      end
    end
  end
end
