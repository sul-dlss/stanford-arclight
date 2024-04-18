# frozen_string_literal: true

require 'uri'
require 'net/http'

# Client for making requests via the ArchivesSpace API
class AspaceClient
  attr_reader :base_url

  # rubocop:disable Metrics/MethodLength
  def initialize(url: Settings.aspace.url,
                 user: ENV.fetch('ASPACE_USER', nil),
                 password: ENV.fetch('ASPACE_PASSWORD', nil))
    raise ArgumentError, 'Please provide the url for ArchivesSpace' unless url

    uri = URI.parse(url)
    @base_url = url
    @user = user
    @password = password

    return unless uri.user

    @user ||= uri.user
    @password ||= uri.password
    @base_url = uri.dup.tap do |u|
      u.user = nil
      u.password = nil
    end.to_s
  end
  # rubocop:enable Metrics/MethodLength

  # Get a list of repositories
  # See https://archivesspace.github.io/archivesspace/api/#get-a-list-of-repositories
  def repositories
    response = authenticated_get('repositories')

    JSON.parse(response)
  end

  # Get the EAD XML representation of a resource
  # See https://archivesspace.github.io/archivesspace/api/#get-an-ead-representation-of-a-resource
  # @example client.resource_description('/repositories/2/resources/5363')
  # @param resource_uri [String] the URI of the resource in ArchivesSpace
  def resource_description(resource_uri)
    unless resource_uri
      raise ArgumentError,
            'Please provide the ArchivesSpace resource URI in the form of ' \
            '/repositories/{REPOSITORY_ID}/resources/{RESOURCE_ID}'
    end

    query_params = 'include_daos=true&numbered_cs=true'
    authenticated_get("#{resource_uri.gsub('/resources/', '/resource_descriptions/')}.xml?#{query_params}")
  end

  # Returns an instance of AspaceQuery that response to :each returning
  # hashes containing an ead id and uri for resources of interest,
  # e.g. {"ead_id"=>"sc0348.xml", "uri"=>"/repositories/2/resources/5363"}
  # @example client.published_resource_uris(repository_id: 2, updated_after: '2023-11-21').each { |r| do something }
  # @param repository_id [Integer] the repository id in ArchivesSpace
  # @param updated_after [String] YYYY-MM-DD optionally limit the response to resources updated after a specific date
  def published_resource_uris(repository_id:, updated_after: nil)
    raise ArgumentError, 'Please provide the ArchivesSpace repository id' unless repository_id

    AspaceQuery.new(client: self, repository_id:, updated_after:)
  end

  # Returns an array of all published resource uris in ASpace for the specified repository
  # e.g. ["/repositories/2/resources/5363", "/repositories/2/resources/3635"]
  # @example client.all_published_resource_uris_by(repository_id: '2')
  # @param repository_id [String] the repository id in ASpace
  def all_published_resource_uris_by(repository_id:)
    ead_ids = []
    published_resource_uris(repository_id:).each do |uri|
      ead_ids << uri['uri']
    end

    ead_ids
  end

  # send an authenticated GET request to Aspace
  def authenticated_get(path, body = nil)
    raise ArgumentError, 'Please provide a path for the request' unless path

    uri = URI.parse("#{@base_url}/#{path}")
    req = Net::HTTP::Get.new(uri)
    req['X-ArchivesSpace-Session'] = session_token
    res = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req, body.to_json)
    end
    raise StandardError, "Unexpected response code #{res.code}: #{res.read_body}" unless res.is_a?(Net::HTTPOK)

    # don't parse JSON here; we might get XML or JSON back.
    res.body
  end

  private

  # get a session token
  # https://archivesspace.github.io/archivesspace/api/#log-in
  def session_token
    @session_token ||= begin
      uri = URI.parse("#{@base_url}/users/#{@user}/login?password=#{@password}")
      res = Net::HTTP.post_form(uri, {})
      raise StandardError, "Unexpected response code #{res.code}: #{res.read_body}" unless res.is_a?(Net::HTTPOK)

      JSON.parse(res.body)['session']
    end
  end

  # Class that wraps logic needed to request resources from ArchivesSpace via
  # a paged query: https://archivesspace.github.io/archivesspace/api/#search-this-repository
  class AspaceQuery
    attr_reader :client, :repository_id, :updated_after

    PAGE_SIZE = 250

    def initialize(client:, repository_id:, updated_after: nil)
      @client = client
      @repository_id = repository_id
      @updated_after = updated_after
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def each(&block)
      return enum_for(:each) unless block_given?

      this_page = 0
      last_page = nil
      while last_page.nil? || this_page < last_page
        this_page += 1

        params = { page: this_page, page_size: PAGE_SIZE, aq: query.to_json }
        path = "repositories/#{repository_id}/search?#{params.to_query}"
        response = client.authenticated_get(path)
        response = JSON.parse(response)
        last_page = response['last_page'].to_i

        response['results'].map { |result| result.slice('ead_id', 'uri') }.each(&block)
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    private

    def query
      { 'query' =>
      { 'jsonmodel_type' => 'boolean_query',
        'op' => 'AND',
        'subqueries' => subqueries } }
    end

    def subqueries
      subqueries = [with_eadid_query, not_suppressed_query, published_query, primary_type_is_resource_query]
      subqueries.append(updated_after_query) if updated_after

      subqueries
    end

    # Limit the response to resources that have an ead id
    def with_eadid_query
      { 'field' => 'ead_id',
        'value' => '*',
        'jsonmodel_type' => 'field_query',
        'negated' => false,
        'literal' => false }
    end

    # Limit the response to resources that are not suppressed
    def not_suppressed_query
      { 'field' => 'suppressed',
        'value' => false,
        'jsonmodel_type' => 'field_query',
        'negated' => false,
        'literal' => false }
    end

    # Limit the response to resources that are published
    def published_query
      { 'field' => 'publish',
        'value' => true,
        'jsonmodel_type' => 'field_query',
        'negated' => false,
        'literal' => false }
    end

    # Limit the response to resources (top container of the finding aid)
    def primary_type_is_resource_query
      { 'field' => 'primary_type',
        'value' => 'resource',
        'jsonmodel_type' => 'field_query',
        'negated' => false,
        'literal' => false }
    end

    # Optionally, limit the response to records updated after the
    # date provided in the form of YYYY-MM-DD
    def updated_after_query
      { 'field' => 'system_mtime',
        'value' => updated_after,
        'comparator' => 'greater_than',
        'precision' => 'DAY',
        'jsonmodel_type' => 'date_field_query',
        'negated' => false,
        'literal' => false }
    end
  end
end
