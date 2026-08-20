# frozen_string_literal: true

module StanfordArclightMcp
  # Executes an ungrouped ArcLight search for the MCP search tool.
  class Search
    class InvalidArguments < ArgumentError; end

    FACET_FILTERS = {
      collections: 'collection',
      creators: 'creators',
      levels: 'level',
      names: 'names',
      repositories: 'repository',
      places: 'places',
      access_subjects: 'access_subjects'
    }.freeze

    def initialize(controller:, **arguments)
      @query = arguments.fetch(:query)
      @controller = controller
      @search_field = arguments.fetch(:search_field, 'keyword')
      @limit = arguments.fetch(:limit, 10)
      @cursor = arguments[:cursor]
      @facet_limit = arguments.fetch(:facet_limit, Facets::DEFAULT_LIMIT)
      @filters = arguments.fetch(:filters, {}) || {}
    end

    def call
      validate_date_range!
      response = search_response
      results = summaries(response)
      result(response, results)
    end

    private

    attr_reader :controller, :cursor, :facet_limit, :filters, :limit, :query, :search_field

    def validate_date_range!
      start_year = filters.dig(:date_range, :start_year)
      end_year = filters.dig(:date_range, :end_year)
      return unless start_year && end_year && start_year > end_year

      raise InvalidArguments, 'date_range.start_year must be less than or equal to date_range.end_year.'
    end

    def result(response, results)
      {
        total_count: response.total,
        returned_count: results.length,
        results:,
        next_cursor: next_cursor(response, results),
        facets: Facets.new(response:, limit: facet_limit).to_a
      }.compact
    end

    def search_response
      search_service.search_results
    end

    def summaries(response)
      response.documents.map { |document| RecordSummary.new(document:, controller:).to_h }
    end

    def search_service
      config = CatalogController.blacklight_config
      state = Blacklight::SearchState.new(search_parameters, config, controller)
      Blacklight::SearchService.new(
        config:,
        search_state: state,
        search_builder_class: StanfordArclightMcp::SearchBuilder,
        controller:
      )
    end

    def search_parameters
      {
        q: query,
        search_field:,
        rows: limit.clamp(1, 20),
        mcp_facet_limit: facet_limit,
        mcp_collection_id: filters[:collection_id],
        f: facet_filters,
        f_inclusive: inclusive_facet_filters,
        range: date_range
      }.merge(cursor_parameters).compact
    end

    def cursor_parameters
      { sort: 'relevance', mcp_cursor: cursor.presence || '*' }
    end

    def next_cursor(response, results)
      return if results.length < limit

      continuation = response['nextCursorMark']
      continuation if continuation.present? && continuation != (cursor.presence || '*')
    end

    def facet_filters
      mapped = FACET_FILTERS.each_with_object({}) do |(input, facet), result|
        values = filters[input]
        result[facet] = values if values.present? && values.one?
      end
      mapped['access'] = ['digital_content'] if filters[:digital_content_only]
      mapped.presence
    end

    def inclusive_facet_filters
      FACET_FILTERS.each_with_object({}) do |(input, facet), result|
        values = filters[input]
        result[facet] = values if values.present? && values.many?
      end.presence
    end

    def date_range
      return unless filters[:date_range]

      {
        date_range: {
          begin: filters.dig(:date_range, :start_year),
          end: filters.dig(:date_range, :end_year)
        }.compact
      }
    end
  end
end
