# frozen_string_literal: true

# Paginated Aspace Search Query that accepts a search query string.
class AspaceSearchQuery
  include AspacePaginatedQuery

  attr_reader :client, :repository_id, :query

  def initialize(client:, repository_id:, query:)
    @client = client
    @repository_id = repository_id
    @query = query
  end
end
