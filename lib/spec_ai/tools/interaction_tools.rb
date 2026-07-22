# frozen_string_literal: true

module SpecAI
  module Tools
    class FindElement < MCP::Tool
      extend Helpers

      tool_name "find_element"
      description "Locate an element and report its tag, text, and attributes. Read-only."
      input_schema(properties: LOCATOR_PROPS.dup, required: %w[strategy value])

      class << self
        def call(strategy:, value:, server_context:)
          guarded(server_context) do |app|
            element = app.session.find([strategy, value])
            meta = app.session.element_metadata(element)
            app.recorder.record(action: :find_element, locator: [strategy, value])
            text("Found: #{meta[:tag]} #{meta[:text].inspect} (id=#{meta[:id].inspect}, " \
                 "name=#{meta[:name].inspect}, type=#{meta[:type].inspect})")
          end
        end
      end
    end

    class Click < MCP::Tool
      extend Helpers

      tool_name "click"
      description "Click an element. Recorded for spec export."
      input_schema(properties: LOCATOR_PROPS.dup, required: %w[strategy value])

      class << self
        def call(strategy:, value:, server_context:)
          guarded(server_context) do |app|
            meta = app.session.click([strategy, value])
            unique = meta.delete(:unique)
            app.recorder.record(action: :click, locator: [strategy, value], element: meta, unique: unique)
            text("Clicked #{strategy}=#{value}. Now at: #{app.session.title} (#{app.session.current_url})")
          end
        end
      end
    end

    class Type < MCP::Tool
      extend Helpers

      tool_name "type"
      description "Type text into an element, replacing any existing value. Pass clear: false " \
                  "to append instead. Password fields are masked in the recording " \
                  "and exported as ENV.fetch(\"SPEC_AI_PASSWORD\")."
      input_schema(
        properties: LOCATOR_PROPS.merge(
          text: { type: "string" },
          clear: { type: "boolean", default: true }
        ),
        required: %w[strategy value text]
      )

      class << self
        # rubocop:disable Style/KeywordParametersOrder
        def call(strategy:, value:, text:, clear: true, server_context:)
          # rubocop:enable Style/KeywordParametersOrder
          guarded(server_context) do |app|
            meta = app.session.type([strategy, value], text, clear: clear)
            unique = meta.delete(:unique)
            if app.session.password_field?(meta)
              app.recorder.record(action: :type, locator: [strategy, value], element: meta,
                                  masked: true, clear: clear, unique: unique)
              text("Typed into #{strategy}=#{value} (password field - value masked in recording).")
            else
              app.recorder.record(action: :type, locator: [strategy, value], element: meta,
                                  value: text, clear: clear, unique: unique)
              text("Typed #{text.inspect} into #{strategy}=#{value}.")
            end
          end
        end
      end
    end

    class SelectOption < MCP::Tool
      extend Helpers

      tool_name "select_option"
      description "Select an option in a <select> by visible text or by value."
      input_schema(
        properties: LOCATOR_PROPS.merge(
          text: { type: "string", description: "Visible option text" },
          option_value: { type: "string", description: "Option value attribute" }
        ),
        required: %w[strategy value]
      )

      class << self
        # rubocop:disable Style/KeywordParametersOrder
        def call(strategy:, value:, text: nil, option_value: nil, server_context:)
          # rubocop:enable Style/KeywordParametersOrder
          text = nil if text == ""
          option_value = nil if option_value == ""
          return error("Provide text or option_value.") if text.nil? && option_value.nil?

          guarded(server_context) do |app|
            meta, by, chosen = app.session.select_option([strategy, value], text: text, value: option_value)
            unique = meta.delete(:unique)
            app.recorder.record(action: :select_option, locator: [strategy, value], element: meta,
                                value: chosen, select_by: by, unique: unique)
            text("Selected #{chosen.inspect} in #{strategy}=#{value}.")
          end
        end
      end
    end

    class Screenshot < MCP::Tool
      extend Helpers

      tool_name "screenshot"
      description "Capture a screenshot of the current page."
      input_schema(properties: {}, required: [])

      class << self
        def call(server_context:)
          guarded(server_context) do |app|
            data = app.session.screenshot_base64
            app.recorder.record(action: :screenshot)
            MCP::Tool::Response.new([{ type: "image", data: data, mimeType: "image/png" }])
          end
        end
      end
    end

    class ExecuteScript < MCP::Tool
      extend Helpers

      tool_name "execute_script"
      description "Run JavaScript in the page. Exported only as a MANUAL review comment, not runnable code."
      input_schema(properties: { script: { type: "string" } }, required: ["script"])

      class << self
        def call(script:, server_context:)
          guarded(server_context) do |app|
            result = app.session.execute_script(script)
            app.recorder.record(action: :execute_script, js: script)
            text("Result: #{result.inspect} (note: exported only as a MANUAL comment in the spec)")
          end
        end
      end
    end

    class WaitFor < MCP::Tool
      extend Helpers

      tool_name "wait_for"
      description "Wait until an element is visible, present, or gone."
      input_schema(
        properties: LOCATOR_PROPS.merge(
          condition: { type: "string", enum: %w[visible present gone] },
          timeout: { type: "integer", default: 10 }
        ),
        required: %w[strategy value condition]
      )

      class << self
        # rubocop:disable Style/KeywordParametersOrder
        def call(strategy:, value:, condition:, timeout: 10, server_context:)
          # rubocop:enable Style/KeywordParametersOrder
          guarded(server_context) do |app|
            app.session.wait_for([strategy, value], condition: condition, timeout: timeout)
            app.recorder.record(action: :wait_for, locator: [strategy, value],
                                condition: condition, timeout: timeout)
            text("Condition met: #{strategy}=#{value} is #{condition}.")
          end
        end
      end
    end
  end
end
