# frozen_string_literal: true

# Module to handle paginated ASpace queries.
module AspacePaginatedQuery
  PAGE_SIZE = 250

  def each(&block)
    return enum_for(:each) unless block_given?

    this_page = 0
    last_page = nil
    while last_page.nil? || this_page < last_page
      this_page += 1
      response = fetch_page(this_page)
      last_page = response['last_page'].to_i

      resources = response['results'].map { |result| result.slice(*keys_to_return) }
      resources.each(&block)
    end
  end

  def query_params
    { q: query }
  end

  def keys_to_return
    ['uri']
  end

  private

  def fetch_page(page_number)
    params = { page: page_number, page_size: PAGE_SIZE }.merge(query_params)
    response = client.authenticated_post("repositories/#{repository_id}/search", params)
    JSON.parse(response)
  end
end
