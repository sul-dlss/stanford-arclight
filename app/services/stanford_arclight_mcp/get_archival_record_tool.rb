# frozen_string_literal: true

module StanfordArclightMcp
  # MCP tool metadata for retrieving an archival record.
  class GetArchivalRecordTool < MCP::Tool
    tool_name 'get_archival_record'
    title 'Get an archival record'
    description 'Retrieve every populated descriptive field supported by the indexed ArcLight record, grouped by ' \
                'archival purpose, with exact access sources. Long descriptions are returned in bounded, ' \
                'deterministic pages without silent truncation.'
    input_schema ToolSchemas::DETAIL_INPUT
    output_schema ToolSchemas::DETAIL_OUTPUT
    annotations(
      read_only_hint: true,
      destructive_hint: false,
      idempotent_hint: true,
      open_world_hint: false
    )

    class << self
      def call(id:, server_context:, cursor: nil,
               max_content_characters: ArchivalRecordContent::DEFAULT_MAX_CHARACTERS)
        record = archival_record(id:, server_context:, cursor:, max_content_characters:)
        success_response(record.to_h)
      rescue Blacklight::Exceptions::RecordNotFound
        error_response('Archival record not found.')
      rescue ArchivalRecordContent::InvalidCursor
        error_response('The archival record continuation cursor is invalid for this record.')
      end

      private

      def archival_record(id:, server_context:, cursor:, max_content_characters:)
        controller = server_context.fetch(:controller)
        service = search_service(controller)
        document = service.fetch(id)
        ancestor_documents = load_ancestor_documents(service, document)
        ArchivalRecord.new(document:, controller:, ancestor_documents:, cursor:, max_content_characters:)
      end

      def load_ancestor_documents(service, document)
        return [] unless ArchivalRecord.requires_ancestor_lookup?(document)

        service.fetch(document.parent_ids)
      end

      def search_service(controller)
        config = CatalogController.blacklight_config
        state = Blacklight::SearchState.new({}, config, controller)
        Blacklight::SearchService.new(config:, search_state: state, controller:)
      end

      def success_response(result)
        MCP::Tool::Response.new(
          [{ type: 'text', text: result.to_json }],
          structured_content: result
        )
      end

      def error_response(message)
        MCP::Tool::Response.new([{ type: 'text', text: message }], error: true)
      end
    end
  end
end
