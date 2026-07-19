# frozen_string_literal: true

require "mcp"

module SpecAI
  class Server
    def self.build(app: App.new)
      MCP::Server.new(
        name: "spec_ai",
        version: SpecAI::VERSION,
        tools: Tools::ALL,
        server_context: { app: app }
      )
    end

    def self.run
      transport = MCP::Server::Transports::StdioTransport.new(build)
      transport.open
    end
  end
end
