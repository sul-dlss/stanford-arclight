# frozen_string_literal: true

module StanfordArclightMcp
  # MCP tool metadata for archival search.
  class SearchArchivalMaterialsTool < MCP::Tool
    tool_name 'search_archival_materials'
    title 'Search archival materials'
    description 'Search Stanford archival collections and their hierarchical components. Results include collection ' \
                'and ancestor context, containers, online content, and facets for refining subsequent searches. ' \
                "Use '*' as the query to browse all records, optionally constrained by filters."
    input_schema ToolSchemas::SEARCH_INPUT
    output_schema ToolSchemas::SEARCH_OUTPUT
    annotations(
      read_only_hint: true,
      destructive_hint: false,
      idempotent_hint: true,
      open_world_hint: false
    )

    def self.call(server_context:, **arguments)
      result = Search.new(
        **arguments,
        controller: server_context.fetch(:controller)
      ).call
      success_response(result)
    rescue Search::InvalidArguments => e
      error_response(e.message)
    end

    def self.success_response(result)
      MCP::Tool::Response.new(
        [{ type: 'text', text: result.to_json }],
        structured_content: result
      )
    end

    def self.error_response(message)
      MCP::Tool::Response.new(
        [{ type: 'text', text: message }],
        error: true
      )
    end

    private_class_method :error_response, :success_response
  end
end
