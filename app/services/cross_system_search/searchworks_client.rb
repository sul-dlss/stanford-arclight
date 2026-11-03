# frozen_string_literal: true

require 'faraday'
require 'json'
require 'uri'

module CrossSystemSearch
  # Thin client for SearchWorks' own public `catalog.json` endpoint - the same
  # endpoint SearchWorks already fetches FROM ArcLight for its own mini-bento
  # (see config/initializers/cors.rb), though the response shape isn't
  # classic Blacklight: no top-level `numFound` - the count lives at
  # `response.pages.total_count` (confirmed against the live endpoint, not
  # documented). No auth, no rate-limit contract with SearchWorks, so
  # deliberately best-effort: any failure returns nil, matching ChatCompletionService.
  class SearchworksClient
    BASE_URL = 'https://searchworks.stanford.edu'

    Result = Struct.new(:total, :docs, keyword_init: true)

    def initialize(timeout: 5)
      @timeout = timeout
    end

    # @return [Result, nil] nil on any request/parse failure
    def search(query, rows: 3)
      response = connection.get('/catalog.json', { q: query, rows: rows })
      return nil unless response.success?

      body = JSON.parse(response.body)
      Result.new(total: body.dig('response', 'pages', 'total_count').to_i, docs: Array(body.dig('response', 'docs')))
    rescue Faraday::Error, JSON::ParserError
      nil
    end

    # @param doc [Hash, nil] a single result from Result#docs
    # @return [Hash, nil] { title:, url: }
    def self.doc_view(doc)
      return nil unless doc

      # NOT `/catalog/{id}` - that 404s. Confirmed by clicking a real result
      # link on the search page itself: individual records live at `/view/{id}`
      # while `/catalog` is reserved for search results.
      { title: title_of(doc), url: "#{BASE_URL}/view/#{doc['id']}" }
    end

    def self.title_of(doc)
      Array(doc['title_display']).first.presence || Array(doc['title_full_display']).first.presence || doc['id']
    end

    # @return [String] the human-facing (not .json) search results page for this query
    def self.search_url(query)
      "#{BASE_URL}/catalog?#{URI.encode_www_form(q: query)}"
    end

    # Grounding text for the LLM prompt only (never rendered) - real title +
    # format, so a "kinds of results" summary can be based on actual formats
    # rather than guessed from a title alone.
    def self.describe_for_prompt(doc)
      return nil unless doc

      format = Array(doc['format_main_ssim']).first.presence || Array(doc['format_hsim']).first.presence
      format ? "#{title_of(doc)} (#{format})" : title_of(doc).to_s
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
