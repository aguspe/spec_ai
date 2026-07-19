# frozen_string_literal: true

require "mcp"

module SpecAI
  module Tools
    LOCATOR_PROPS = {
      strategy: { type: "string", enum: BrowserSession::STRATEGIES },
      value: { type: "string" }
    }.freeze

    module Helpers
      def app(server_context)
        server_context.fetch(:app)
      end

      def text(msg)
        MCP::Tool::Response.new([{ type: "text", text: msg }])
      end

      def error(msg)
        text("ERROR: #{msg}")
      end

      def guarded(server_context)
        yield app(server_context)
      rescue SessionNotStartedError
        error("No browser session. Call start_browser first.")
      rescue SessionDeadError
        error("Browser session lost (crashed or closed manually). Recording preserved - " \
              "call start_browser to continue, or export_spec to keep what you have.")
      rescue ElementNotFoundError => e
        error(e.message)
      rescue Selenium::WebDriver::Error::TimeoutError => e
        error("Timed out: #{e.message}")
      rescue Selenium::WebDriver::Error::InvalidSelectorError => e
        error("Invalid selector: #{e.message}")
      rescue Selenium::WebDriver::Error::WebDriverError => e
        error("WebDriver error: #{e.message}")
      end
    end
  end
end
