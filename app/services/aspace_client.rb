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
    published_resource_uris(repository_id:).each.to_a.pluck('uri')
  end

  def published_resource_with_updated_component_uris(repository_id:, updated_after:, uris_to_exclude: nil)
    raise ArgumentError, 'Please provide the ArchivesSpace repository id' unless repository_id
    raise ArgumentError, 'Please provide the updated after date' unless updated_after

    published_resource_with_modified_components_query(repository_id:, updated_after:, uris_to_exclude:)
  end

  # send an authenticated GET request to ASpace
  def authenticated_get(path, body = nil)
    send_request(:get, path, body)
  end

  # send an authenticated POST request to ASpace
  def authenticated_post(path, body = {})
    send_request(:post, path, body)
  end

  private

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
  def send_request(method, path, body = nil)
    raise ArgumentError, 'Please provide a path for the request' unless path

    uri = URI.parse("#{@base_url}/#{path}")
    req = case method
          when :get
            Net::HTTP::Get.new(uri)
          when :post
            Net::HTTP::Post.new(uri).tap do |request|
              request.set_form_data(body) if body
            end
          else
            raise ArgumentError, "Unsupported method: #{method}"
          end

    req['X-ArchivesSpace-Session'] = session_token
    res = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req, method == :get && body ? body.to_json : nil)
    end
    raise StandardError, "Unexpected response code #{res.code}: #{res.read_body}" unless res.is_a?(Net::HTTPOK)

    # don't parse JSON here; we might get XML or JSON back.
    res.body
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength

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

  # This is a potentially expensive query that checks for updates at the component
  # (e.g., Archival Object) level, catching the resources ASpace might not report.
  # See the following for context:
  # https://github.com/sul-dlss/stanford-arclight/issues/551
  # https://github.com/archivesspace/archivesspace/issues/856
  # https://github.com/archivesspace/archivesspace/pull/1374
  # Setting uris_to_exclude allows us to reduce the search size, which speeds up the query dramatically
  def published_resource_with_modified_components_query(repository_id:, updated_after:, uris_to_exclude: nil)
    # Get all resources, regardless of resource published/suppressed status, with modified components
    query = AspaceQuery.new(client: self, repository_id:, updated_after:)
                       .query_components
                       .select_fields(['resource'])
    query.excluding_resource_uris(uris_to_exclude) if uris_to_exclude.present?
    result = query.each.to_a.uniq
    uris = result.map { |resource| resource['resource'] }

    # Query ASpace to reduce to resources that are published/not suppressed/have eadids.
    # Important to not pass updated_after here. ASpace doesn't think these are updated.
    AspaceQuery.new(client: self, repository_id:).restrict_results_to_uris(uris)
  end

  # Class that wraps logic needed to request resources from ArchivesSpace via
  # a paged query: https://archivesspace.github.io/archivesspace/api/#search-this-repository
  # rubocop:disable Metrics/ClassLength
  class AspaceQuery
    attr_reader :client, :fields, :query_type, :repository_id, :resource_uris_to_exclude,
                :restrict_result_uris, :updated_after

    PAGE_SIZE = 250

    def initialize(client:, repository_id:, updated_after: nil)
      @client = client
      @repository_id = repository_id
      @updated_after = updated_after

      # Defaults that can be set by the chaining methods
      @query_type = :resource
      @fields = %w[ead_id uri]
      @restrict_result_uris = nil
      @resource_uris_to_exclude = nil
    end

    def excluding_resource_uris(uris)
      @resource_uris_to_exclude = uris
      self
    end

    def restrict_results_to_uris(uris)
      @restrict_result_uris = uris
      self
    end

    def query_components
      @query_type = :component
      self
    end

    def select_fields(fields)
      @fields = fields
      self
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def each(&block)
      return enum_for(:each) unless block_given?

      this_page = 0
      last_page = nil
      while last_page.nil? || this_page < last_page
        this_page += 1

        params = { page: this_page, page_size: PAGE_SIZE, aq: query.to_json }
        path = "repositories/#{repository_id}/search"
        response = client.authenticated_post(path, params)
        response = JSON.parse(response)
        last_page = response['last_page'].to_i

        resources = response['results'].map { |result| result.slice(*fields) }
        resources.each(&block)
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
      return component_subqueries if query_type == :component

      resource_subqueries
    end

    def resource_subqueries
      subqueries = [with_eadid_query, not_suppressed_query, published_query, primary_type_is_resource_query]
      subqueries.append(updated_after_query) if updated_after
      subqueries.append(restrict_to_uris_query) if restrict_result_uris

      subqueries
    end

    def component_subqueries
      subqueries = [with_resource_query]
      subqueries.append(updated_after_query) if updated_after
      subqueries.append(exclude_known_resource_query) if resource_uris_to_exclude

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

    # Limit the response to records with resource values that are not in the exclusion list
    def exclude_known_resource_query
      { 'jsonmodel_type' => 'boolean_query',
        'op' => 'AND',
        'subqueries' =>
        resource_uris_to_exclude.map { |resource| excluded_resource_field_query(resource) } }
    end

    def excluded_resource_field_query(resource_uri)
      { 'field' => 'resource',
        'value' => resource_uri,
        'jsonmodel_type' => 'field_query',
        'negated' => true,
        'literal' => true }
    end

    # Limit the response to records with resource values
    def with_resource_query
      { 'field' => 'resource',
        'value' => '[* TO *]',
        'jsonmodel_type' => 'field_query',
        'negated' => false,
        'literal' => false }
    end

    # Limit the response to records with URIs found in an allowed list
    def restrict_to_uris_query
      { 'jsonmodel_type' => 'boolean_query',
        'op' => 'OR',
        'subqueries' =>
        restrict_result_uris.map { |uri| restrict_uri_field_query(uri) } }
    end

    def restrict_uri_field_query(uri)
      { 'field' => 'uri',
        'value' => uri,
        'jsonmodel_type' => 'field_query',
        'negated' => false,
        'literal' => true }
    end
  end
  # rubocop:enable Metrics/ClassLength
end
