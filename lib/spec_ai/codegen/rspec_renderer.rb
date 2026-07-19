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

      def body_lines
        @steps.flat_map { |step| lines_for(step) }
      end

      def loc(locator)
        strategy, value = locator
        "#{strategy}: #{value.inspect}"
      end

      def lines_for(step) # rubocop:disable Metrics/CyclomaticComplexity
        case step.action
        when :navigate then ["@driver.navigate.to #{step.value.inspect}"]
        when :click then ["@driver.find_element(#{loc(step.locator)}).click"]
        when :type then type_lines(step)
        when :select_option then [select_line(step)]
        when :wait_for then [wait_line(step)]
        when :execute_script then [manual_comment(step)]
        when :assert_text then [assert_text_line(step)]
        when :assert_title then ["expect(@driver.title).to eq(#{step.expected.inspect})"]
        when :assert_element then [assert_element_line(step)]
        when :assert_url then ["expect(@driver.current_url).to match(Regexp.new(#{step.expected.inspect}))"]
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
        waiter = step.timeout == 10 ? "@wait.until" : "Selenium::WebDriver::Wait.new(timeout: #{step.timeout}).until"
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

      def assert_text_line(step)
        target = step.scope ? "@driver.find_element(#{loc(step.scope)})" : '@driver.find_element(tag_name: "body")'
        "expect(#{target}.text).to include(#{step.expected.inspect})"
      end

      def assert_element_line(step)
        if step.condition == "visible"
          "expect(@driver.find_element(#{loc(step.locator)}).displayed?).to be true"
        else
          "expect(@driver.find_elements(#{loc(step.locator)}).any?).to be true"
        end
      end
    end
  end
end
