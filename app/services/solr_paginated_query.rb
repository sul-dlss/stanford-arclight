# frozen_string_literal: true

# Class to handle paginated Solr queries for internal use (background jobs, rake tasks, etc.).
class SolrPaginatedQuery
  PAGE_SIZE = 250

  # @example SolrPaginatedQuery.new(filter_queries: { sul_ark_shoulder_ssi: 's1' },
  #                                 fields_to_return: %w[id title_ssm])
  # @param filter_queries [Hash] where keys are Solr field names and values are the values to filter by
  # @param fields_to_return [Array<String>] the Solr field names to return in the results
  def initialize(filter_queries:, fields_to_return:)
    @filter_queries = filter_queries
    @fields_to_return = fields_to_return
  end

  # Returns an array of all documents matching the filter queries,
  # with only the fields specified in `fields_to_return`.
  # # @return [Array<Array>] an array of arrays of values [['ars-0043', ['Ambassador Auditorium Collection']]]
  def all
    each.to_a
  end

  private

  def filter_query
    @filter_queries.map { |key, value| "#{key}:\"#{value}\"" }
  end

  def fields
    @fields_to_return.join(',')
  end

  def each_response_handler(response)
    response.dig('response', 'docs').pluck(*@fields_to_return)
  end

  # rubocop:disable Metrics/MethodLength
  def each(&)
    return enum_for(:each) unless block_given?

    this_page = 0
    last_page = nil

    while last_page.nil? || this_page < last_page
      response = repository.search(
        rows: PAGE_SIZE,
        start: this_page,
        fl: fields,
        fq: filter_query,
        sort: 'id ASC',
        facet: false
      )

      this_page += PAGE_SIZE
      last_page = response.dig('response', 'numFound')

      each_response_handler(response).each(&)
    end
  end
  # rubocop:enable Metrics/MethodLength

  delegate :repository, to: :blacklight_config

  def blacklight_config
    @blacklight_config ||= CatalogController.blacklight_config.configure
  end
end
