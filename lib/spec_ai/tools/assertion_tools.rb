# frozen_string_literal: true

module SpecAI
  module Tools
    class AssertText < MCP::Tool
      extend Helpers

      tool_name "assert_text"
      description "Assert text is present on the page (or within a scoped element). " \
                  "Passing assertions become expect(...) lines in the exported spec."
      input_schema(
        properties: {
          text: { type: "string" },
          scope_strategy: { type: "string", enum: BrowserSession::STRATEGIES },
          scope_value: { type: "string" }
        },
        required: ["text"]
      )

      class << self
        # rubocop:disable Style/KeywordParametersOrder
        def call(text:, scope_strategy: nil, scope_value: nil, server_context:)
          # rubocop:enable Style/KeywordParametersOrder
          guarded(server_context) do |app|
            scope = scope_strategy && scope_value ? [scope_strategy, scope_value] : nil
            actual = scope ? app.session.find(scope).text : app.session.execute_script("return document.body.innerText")
            if actual.to_s.include?(text)
              app.recorder.record(action: :assert_text, expected: text, scope: scope)
              text("Assertion passed: page contains #{text.inspect}.")
            else
              error("Assertion failed: expected #{text.inspect} - actual: #{actual.to_s[0, 200].inspect}")
            end
          end
        end
      end
    end

    class AssertTitle < MCP::Tool
      extend Helpers

      tool_name "assert_title"
      description "Assert the page title equals the expected string."
      input_schema(properties: { expected: { type: "string" } }, required: ["expected"])

      class << self
        def call(expected:, server_context:)
          guarded(server_context) do |app|
            actual = app.session.title
            if actual == expected
              app.recorder.record(action: :assert_title, expected: expected)
              text("Assertion passed: title is #{expected.inspect}.")
            else
              error("Assertion failed: expected title #{expected.inspect} - actual: #{actual.inspect}")
            end
          end
        end
      end
    end

    class AssertElement < MCP::Tool
      extend Helpers

      tool_name "assert_element"
      description "Assert an element is visible or present."
      input_schema(
        properties: LOCATOR_PROPS.merge(state: { type: "string", enum: %w[visible present] }),
        required: %w[strategy value state]
      )

      class << self
        def call(strategy:, value:, state:, server_context:)
          guarded(server_context) do |app|
            app.session.wait_for([strategy, value], condition: state, timeout: 2)
            app.recorder.record(action: :assert_element, locator: [strategy, value], condition: state)
            text("Assertion passed: #{strategy}=#{value} is #{state}.")
          rescue Selenium::WebDriver::Error::TimeoutError
            error("Assertion failed: expected #{strategy}=#{value} to be #{state} - it is not.")
          end
        end
      end
    end

    class AssertUrl < MCP::Tool
      extend Helpers

      tool_name "assert_url"
      description "Assert the current URL matches a Ruby regexp pattern (string)."
      input_schema(properties: { pattern: { type: "string" } }, required: ["pattern"])

      class << self
        def call(pattern:, server_context:)
          # rubocop:disable Lint/NoReturnInBeginEndBlocks
          regexp = begin
            Regexp.new(pattern)
          rescue RegexpError => e
            return error("Invalid pattern: #{e.message}")
          end
          # rubocop:enable Lint/NoReturnInBeginEndBlocks
          guarded(server_context) do |app|
            actual = app.session.current_url
            if regexp.match?(actual)
              app.recorder.record(action: :assert_url, expected: pattern)
              text("Assertion passed: url matches /#{pattern}/.")
            else
              error("Assertion failed: expected url to match /#{pattern}/ - actual: #{actual.inspect}")
            end
          end
        end
      end
    end
  end
end
