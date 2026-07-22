# frozen_string_literal: true

require "erb"

module SpecAI
  module Codegen
    class RspecRenderer
      TEMPLATE = File.read(File.expand_path("templates/rspec_spec.rb.erb", __dir__))
      HEADLESS_FLAGS = { "chrome" => "--headless=new", "edge" => "--headless=new", "firefox" => "-headless" }.freeze

      def self.render(steps:, description:)
        new(steps, description).render
      end

      def initialize(steps, description)
        @steps = steps
        @description = description
      end

      def render
        ERB.new(TEMPLATE, trim_mode: "-").result(binding)
      end

      private

      def start_step
        @steps.find { |s| s.action == :start_browser }
      end

      def browser
        start_step&.value || "chrome"
      end

      def headless?
        !!start_step&.headless && HEADLESS_FLAGS.key?(browser)
      end

      def headless_flag
        HEADLESS_FLAGS.fetch(browser)
      end

      def assertions?
        @steps.any? { |s| s.action.to_s.start_with?("assert_") }
      end

      def warnings
        starts = @steps.count { |s| s.action == :start_browser }
        return [] if starts <= 1

        ["# WARNING: this recording has #{starts} browser sessions merged into one example.",
         "# The before hook uses the first browser (#{browser}). Call reset_recording",
         "# between sessions for a clean spec."]
      end

      def body_lines
        @steps.flat_map { |step| lines_for(step) }
      end

      def loc(locator)
        strategy, value = locator
        "#{strategy}: #{value.inspect}"
      end

      # 1-based position among screenshot steps, by object identity so repeated
      # bare screenshot steps get distinct filenames.
      def screenshot_index(step)
        seen = 0
        @steps.each do |candidate|
          next unless candidate.action == :screenshot

          seen += 1
          return seen if candidate.equal?(step)
        end
        seen
      end

      def lines_for(step) # rubocop:disable Metrics/CyclomaticComplexity
        case step.action
        when :navigate then ["@driver.navigate.to #{step.value.inspect}"]
        when :click then ["@driver.find_element(#{loc(step.locator)}).click"]
        when :type then type_lines(step)
        when :select_option then [select_line(step)]
        when :wait_for then [wait_line(step)]
        when :execute_script then [manual_comment(step)]
        when :screenshot then ["@driver.save_screenshot(\"screenshot-#{screenshot_index(step)}.png\")"]
        when :assert_text then assert_text_lines(step)
        when :assert_title then assert_title_lines(step)
        when :assert_element then assert_element_lines(step)
        when :assert_url then assert_url_lines(step)
        else []
        end
      end

      def type_lines(step)
        value = step.masked ? 'ENV.fetch("SPEC_AI_PASSWORD")' : step.value.inspect
        lines = []
        lines << "@driver.find_element(#{loc(step.locator)}).clear" if step.clear
        lines << "@driver.find_element(#{loc(step.locator)}).send_keys #{value}"
        lines
      end

      def select_line(step)
        "Selenium::WebDriver::Support::Select.new(@driver.find_element(#{loc(step.locator)}))" \
          ".select_by(#{step.select_by.inspect}, #{step.value.inspect})"
      end

      def wait_line(step)
        waiter =
          if step.timeout == 10
            "@wait.until"
          else
            "Selenium::WebDriver::Wait.new(timeout: #{step.timeout}, ignore: @ignored).until"
          end
        inner =
          case step.condition
          when "visible" then "@driver.find_element(#{loc(step.locator)}).displayed?"
          when "present" then "@driver.find_elements(#{loc(step.locator)}).any?"
          when "gone" then "@driver.find_elements(#{loc(step.locator)}).empty?"
          end
        "#{waiter} { #{inner} }"
      end

      def manual_comment(step)
        snippet = step.js.to_s.lines.first.to_s.strip[0, 60]
        "# MANUAL: review this step - execute_script recorded: #{snippet}"
      end

      # Assertions export as a wait followed by the expect: the live check does not
      # race page loads (tool round-trips add latency), but a replayed spec does.
      def assert_text_lines(step)
        target = step.scope ? "@driver.find_element(#{loc(step.scope)})" : '@driver.find_element(tag_name: "body")'
        ["@wait.until { #{target}.text.include?(#{step.expected.inspect}) }",
         "expect(#{target}.text).to include(#{step.expected.inspect})"]
      end

      def assert_title_lines(step)
        ["@wait.until { @driver.title == #{step.expected.inspect} }",
         "expect(@driver.title).to eq(#{step.expected.inspect})"]
      end

      def assert_element_lines(step)
        if step.condition == "visible"
          ["@wait.until { @driver.find_element(#{loc(step.locator)}).displayed? }",
           "expect(@driver.find_element(#{loc(step.locator)}).displayed?).to be true"]
        else
          ["@wait.until { @driver.find_elements(#{loc(step.locator)}).any? }",
           "expect(@driver.find_elements(#{loc(step.locator)}).any?).to be true"]
        end
      end

      def assert_url_lines(step)
        ["@wait.until { @driver.current_url.match?(Regexp.new(#{step.expected.inspect})) }",
         "expect(@driver.current_url).to match(Regexp.new(#{step.expected.inspect}))"]
      end
    end
  end
end
