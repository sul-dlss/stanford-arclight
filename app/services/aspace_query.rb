# frozen_string_literal: true

# Class that wraps logic needed to request records from ArchivesSpace via
# a paged query: https://archivesspace.github.io/archivesspace/api/#search-this-repository
# rubocop:disable Metrics/ClassLength
class AspaceQuery
  include AspacePaginatedQuery

  attr_reader :client, :repository_id, :primary_type, :updated_after, :options

  # @param client [AspaceClient] the client used to make requests
  # @param repository_id [Integer] the ID of the repository
  # @param primary_type [String] the primary record type to query, defaults to 'resource'
  # @param updated_after [String] YYYY-MM-DD optionally limit to records that have been updated after a specific date
  # @param options [Hash] additional query options with keys:
  #   - :published [Boolean] published status the records must have
  #   - :suppressed [Boolean] suppressed status the records must have
  #   - :contains_fields [Array<String>] fields that must be present in the records, defaults to ['ead_id']
  #   - :contains_type [string] type that the records must contain
  #   - :select_fields [Array<String>] fields to be returned in the results, defaults to ['ead_id', 'uri']
  #   - :limit_results_to_uris [Array<String>] URIs to restrict the results to
  #   - :exclude_field_values [Hash] field values to exclude from the results, e.g., {'resource' => ['...']}
  def initialize(client:, repository_id:, primary_type: 'resource', updated_after: nil, options: {})
    @client = client
    @repository_id = repository_id
    @primary_type = primary_type
    @updated_after = updated_after
    @options = options
  end

  def query_params
    { aq: query.to_json }
  end

  def keys_to_return
    select_fields_option
  end

  private

  def query
    { 'query' =>
    { 'jsonmodel_type' => 'boolean_query',
      'op' => 'AND',
      'subqueries' => subqueries } }
  end

  def subqueries
    subqueries = [not_suppressed_query, published_query, updated_after_query, primary_type_is_query,
                  type_is_one_of_query, restrict_to_uris_query]
    contains_fields_option&.each { |field| subqueries.append(with_field_query(field)) }
    exclude_field_values_option&.each { |field, values| subqueries.append(exclude_field_values_query(field, values)) }
    subqueries.compact
  end

  def published_option
    options[:published]
  end

  def suppressed_option
    options[:suppressed]
  end

  def contains_fields_option
    options[:contains_fields] || ['ead_id']
  end

  def contains_type_option
    options[:contains_type]
  end

  def select_fields_option
    options[:select_fields] || %w[ead_id uri]
  end

  def limit_results_to_uris_option
    options[:limit_results_to_uris]
  end

  def exclude_field_values_option
    options[:exclude_field_values]
  end

  # Limit the response to records that contain a specific field
  def with_field_query(field)
    { 'field' => field,
      'value' => '*',
      'jsonmodel_type' => 'field_query',
      'negated' => false,
      'literal' => false }
  end

  # Limit the response to records that are not suppressed
  def not_suppressed_query
    return unless suppressed_option

    { 'field' => 'suppressed',
      'value' => suppressed_option,
      'jsonmodel_type' => 'field_query',
      'negated' => false,
      'literal' => false }
  end

  # Limit the response to records that are published
  def published_query
    return unless published_option

    { 'field' => 'publish',
      'value' => published_option,
      'jsonmodel_type' => 'field_query',
      'negated' => false,
      'literal' => false }
  end

  # Limit the response to records of the given primary type
  def primary_type_is_query
    return unless primary_type

    { 'field' => 'primary_type',
      'value' => primary_type,
      'jsonmodel_type' => 'field_query',
      'negated' => false,
      'literal' => false }
  end

  # Limit the response to records that have at least one type matching the given type
  def type_is_one_of_query
    return unless contains_type_option

    { 'field' => 'types',
      'value' => contains_type_option,
      'jsonmodel_type' => 'field_query',
      'negated' => false,
      'literal' => true }
  end

  # Optionally, limit the response to records updated after the
  # date provided in the form of YYYY-MM-DD
  def updated_after_query
    return unless updated_after

    { 'field' => 'system_mtime',
      'value' => updated_after,
      'comparator' => 'greater_than',
      'precision' => 'DAY',
      'jsonmodel_type' => 'date_field_query',
      'negated' => false,
      'literal' => false }
  end

  # Limit the response to records with field values that are not in the exclusion list
  def exclude_field_values_query(field, values)
    return unless field && values.present?

    { 'jsonmodel_type' => 'boolean_query',
      'op' => 'AND',
      'subqueries' =>
      values.map { |value| exclude_field_value_query_component(field, value) } }
  end

  def exclude_field_value_query_component(field, value)
    { 'field' => field,
      'value' => value,
      'jsonmodel_type' => 'field_query',
      'negated' => true,
      'literal' => true }
  end

  # Limit the response to records with URIs found in an allowed list
  def restrict_to_uris_query
    return unless limit_results_to_uris_option

    { 'jsonmodel_type' => 'boolean_query',
      'op' => 'OR',
      'subqueries' => limit_results_to_uris_option.map { |uri| restrict_uri_field_query(uri) } }
  end

  def restrict_uri_field_query(uri)
    return unless uri

    { 'field' => 'uri',
      'value' => uri,
      'jsonmodel_type' => 'field_query',
      'negated' => false,
      'literal' => true }
  end
end
# rubocop:enable Metrics/ClassLength
