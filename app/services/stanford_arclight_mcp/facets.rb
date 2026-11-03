# frozen_string_literal: true

module StanfordArclightMcp
  # Projects the configured archival facets into the compact MCP response shape.
  class Facets
    DEFAULT_LIMIT = 5

    FIELDS = {
      collections: { field: 'collection_ssim', label: 'Collection' },
      creators: { field: 'creator_ssim', label: 'Creators' },
      levels: { field: 'level_ssim', label: 'Level' },
      names: { field: 'names_ssim', label: 'Names' },
      repositories: { field: 'repository_ssim', label: 'Repository' },
      places: { field: 'geogname_ssim', label: 'Places' },
      access_subjects: { field: 'access_subjects_ssim', label: 'Access Subjects' }
    }.freeze

    def initialize(response:, limit: DEFAULT_LIMIT)
      @response = response
      @limit = limit
    end

    def to_a
      FIELDS.filter_map { |key, config| facet(key, config) }
    end

    private

    attr_reader :limit, :response

    def facet(key, config)
      pairs = response.facet_fields.fetch(config[:field], []).each_slice(2).first(limit + 1)
      values = pairs.first(limit).map { |value, count| { value:, count: } }
      return if values.empty?

      { key:, label: config[:label], values:, truncated: pairs.length > limit }
    end
  end
end
