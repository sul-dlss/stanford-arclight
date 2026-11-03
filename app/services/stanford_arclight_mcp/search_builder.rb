# frozen_string_literal: true

module StanfordArclightMcp
  # Adds MCP-only query constraints without replacing Blacklight's user query.
  class SearchBuilder < ::SearchBuilder
    self.default_processor_chain += %i[add_mcp_collection_filter add_mcp_cursor add_mcp_facet_limits]

    def add_mcp_collection_filter(solr_parameters)
      collection_id = blacklight_params[:mcp_collection_id]
      return if collection_id.blank?

      solr_parameters.append_filter_query(facet_value_to_fq_string('_root_', collection_id))
    end

    def add_mcp_cursor(solr_parameters)
      cursor = blacklight_params[:mcp_cursor]
      return if cursor.blank?

      solr_parameters[:cursorMark] = cursor
      solr_parameters[:sort] = [solr_parameters[:sort], 'id asc'].compact.join(', ')
    end

    def add_mcp_facet_limits(solr_parameters)
      limit = blacklight_params[:mcp_facet_limit] || Facets::DEFAULT_LIMIT
      Facets::FIELDS.each_value do |config|
        solr_parameters[:"f.#{config[:field]}.facet.limit"] = limit + 1
      end
    end
  end
end
