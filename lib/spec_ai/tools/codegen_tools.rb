# frozen_string_literal: true

require "fileutils"

module SpecAI
  module Tools
    class ExportSpec < MCP::Tool
      extend Helpers

      tool_name "export_spec"
      description "Export the recorded session as a runnable spec. " \
                  "format: rspec (plain selenium-webdriver, default) or capybara (Rails system spec)."
      input_schema(
        properties: {
          description: { type: "string", description: "Spec description, e.g. 'Login flow'" },
          format: { type: "string", enum: %w[rspec capybara], default: "rspec" },
          path: { type: "string", description: "Optional file path to write the spec to" }
        },
        required: ["description"]
      )

      RENDERERS = {
        "rspec" => Codegen::RspecRenderer,
        "capybara" => Codegen::CapybaraRenderer
      }.freeze

      class << self
        # rubocop:disable Style/KeywordParametersOrder
        def call(description:, format: "rspec", path: nil, server_context:)
          # rubocop:enable Style/KeywordParametersOrder
          app = app(server_context)
          return error("Nothing recorded yet - drive the browser first, then export.") if app.recorder.empty?

          source = RENDERERS.fetch(format).render(steps: app.recorder.steps, description: description)
          if path
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, source)
            text("Spec written to #{path}\n\n#{source}")
          else
            text(source)
          end
        end
      end
    end

    class ResetRecording < MCP::Tool
      extend Helpers

      tool_name "reset_recording"
      description "Clear the recorded steps. The browser stays open."
      input_schema(properties: {}, required: [])

      class << self
        def call(server_context:)
          app(server_context).recorder.reset
          text("Recording cleared. Browser still open.")
        end
      end
    end
  end
end
