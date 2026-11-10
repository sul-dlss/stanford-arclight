# frozen_string_literal: true

# Paginated Aspace Search Query that accepts a search query string.
class AspaceSearchQuery
  include AspacePaginatedQuery

  attr_reader :client, :repository_id, :query, :type, :keys_to_return

  # @param client [AspaceClient] the client used to make requests
  # @param repository_id [Integer] the ID of the repository
  # @param query [String] the search query string
  # @param type [String] optionally limit results to a record type, such as 'resource'
  # @param keys_to_return [Array<String>] fields to be returned in the results, defaults to ['uri']
  def initialize(client:, repository_id:, query:, type: nil, keys_to_return: ['uri'])
    @client = client
    @repository_id = repository_id
    @query = query
    @type = type
    @keys_to_return = keys_to_return
  end

  def query_params
    { q: query, 'type[]': type }.compact
  end
end
