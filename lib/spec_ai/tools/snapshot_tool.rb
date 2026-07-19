# frozen_string_literal: true

module SpecAI
  module Tools
    class Snapshot < MCP::Tool
      extend Helpers

      tool_name "snapshot"
      description "Compact outline of interactive elements on the page with ready-to-use locators. " \
                  "Call this before interacting to pick reliable locators."
      input_schema(properties: {}, required: [])

      class << self
        def call(server_context:)
          guarded(server_context) do |app|
            entries = app.session.snapshot
            app.recorder.record(action: :snapshot)
            lines = entries.map { |e| format_entry(e) }
            text(["Interactive elements (#{entries.size}):", *lines].join("\n"))
          end
        end

        private

        def format_entry(entry)
          locator =
            if entry["id"] && !entry["id"].empty? then "locator: id=#{entry['id']}"
            elsif entry["name"] && !entry["name"].empty? then "locator: name=#{entry['name']}"
            else "no unique locator - inspect with find_element or use css/xpath"
            end
          %(- #{entry['tag']} "#{entry['text']}" [#{locator}])
        end
      end
    end
  end
end
