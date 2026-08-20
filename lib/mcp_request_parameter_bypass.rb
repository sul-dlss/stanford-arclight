# frozen_string_literal: true

# Leaves MCP request bodies for the protocol transport to size-limit and parse.
class McpRequestParameterBypass
  REQUEST_PARAMETERS_KEY = 'action_dispatch.request.request_parameters'

  def initialize(app)
    @app = app
  end

  def call(env)
    env[REQUEST_PARAMETERS_KEY] = {} if env['PATH_INFO'] == '/mcp'
    @app.call(env)
  end
end
