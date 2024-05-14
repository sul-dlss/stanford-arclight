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

    AspaceQuery.new(client: self, repository_id:, updated_after:, options: { published: true, suppressed: false })
  end

  # Returns an array of all published resource uris in ASpace for the specified repository
  # e.g. ["/repositories/2/resources/5363", "/repositories/2/resources/3635"]
  # @example client.all_published_resource_uris_by(repository_id: '2')
  # @param repository_id [String] the repository id in ASpace
  def all_published_resource_uris_by(repository_id:)
    published_resource_uris(repository_id:).each.to_a.pluck('uri')
  end

  # Returns an instance of AspaceQuery that response to :each returning
  # hashes containing an ead id and uri for resources of interest,
  # e.g. {"ead_id"=>"sc0348.xml", "uri"=>"/repositories/2/resources/5363"}
  # This query can be slow. It is recommended to pass the result of a faster query to 'uris_to_exclude'.
  # See https://github.com/sul-dlss/stanford-arclight/issues/551.
  # This may be able to be removed once on ArchivesSpace v3.5.0+.
  # @param repository_id [Integer] the repository id in ArchivesSpace
  # @param updated_after [String] YYYY-MM-DD limits the response to resources updated after a specific date
  # @param uris_to_exclude [Array] optionally limit the response, excluding the given resource uris
  def published_resource_with_updated_component_uris(repository_id:, updated_after:, uris_to_exclude: nil)
    raise ArgumentError, 'Please provide the ArchivesSpace repository id' unless repository_id
    raise ArgumentError, 'Please provide the updated after date' unless updated_after

    objects_with_resource_link = { contains_fields: ['resource'],
                                   select_fields: ['resource'],
                                   exclude_field_values: { 'resource' => uris_to_exclude } }
    resources_with_modified_objects = AspaceQuery.new(client: self, repository_id:, primary_type: nil, updated_after:,
                                                      options: objects_with_resource_link).each.to_a.uniq

    uris = resources_with_modified_objects.map { |resource| resource['resource'] }

    # Query ASpace to reduce to resources that are published/not suppressed/have eadids.
    # Important to not pass updated_after here. ASpace doesn't think these are updated.
    filter_to_resources = { published: true, suppressed: false, limit_results_to_uris: uris }
    AspaceQuery.new(client: self, repository_id:, options: filter_to_resources)
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
end
