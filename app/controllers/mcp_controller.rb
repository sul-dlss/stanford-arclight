# frozen_string_literal: true

# Serves Stanford ArcLight's read-only Model Context Protocol tools.
class McpController < ApplicationController
  SERVER_METADATA = {
    name: 'stanford_arclight',
    title: 'Stanford Archives',
    version: '0.1.0',
    instructions: 'Search Stanford archival collections and their components.'
  }.freeze

  skip_forgery_protection

  def create
    status, headers, body = transport.handle_request(request)
    response.headers.merge!(headers)

    if body.empty?
      head status
    else
      render body: body.join, status:, content_type: headers['content-type']
    end
  end

  private

  def transport
    MCP::Server::Transports::StreamableHTTPTransport.new(
      server,
      stateless: true,
      enable_json_response: true,
      allowed_hosts:
    )
  end

  def server
    MCP::Server.new(
      **SERVER_METADATA,
      tools: tools,
      configuration: MCP::Configuration.new(validate_tool_call_results: true),
      server_context: { controller: self }
    )
  end

  def allowed_hosts
    Settings.mcp.allowed_hosts.split(',').map(&:strip)
  end

  def tools
    [
      StanfordArclightMcp::SearchArchivalMaterialsTool,
      StanfordArclightMcp::GetArchivalRecordTool
    ]
  end
end
