# frozen_string_literal: true

require "erb"
require "uri"

module SpecAI
  module Codegen
    class CapybaraRenderer
      TEMPLATE = File.read(File.expand_path("templates/capybara_spec.rb.erb", __dir__))

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

      def assertions?
        @steps.any? { |s| s.action.to_s.start_with?("assert_") }
      end

      def warnings
        lines = []
        starts = @steps.count { |s| s.action == :start_browser }
        if starts > 1
          lines << "# WARNING: this recording has #{starts} browser sessions merged into one example; " \
                   "re-record or call reset_recording between sessions for a clean spec."
        end
        hosts = navigate_hosts
        if hosts.size > 1
          lines << "# WARNING: this recording spans multiple hosts (#{hosts.join(', ')}); visit paths are " \
                   "relative to a single Capybara app_host and will not target the other host(s)."
        end
        lines
      end

      def navigate_hosts
        @steps.select { |s| s.action == :navigate }.filter_map { |s| host_of(s.value) }.uniq
      end

      def host_of(url)
        host = URI.parse(url).host
        host unless host.nil? || host.empty?
      rescue URI::InvalidURIError
        nil
      end

      def body_lines
        @steps.flat_map { |step| lines_for(step) }
      end

      def lines_for(step) # rubocop:disable Metrics/CyclomaticComplexity
        case step.action
        when :navigate then ["visit #{relative(step.value).inspect}"]
        when :click then [click_line(step)]
        when :type then [type_line(step)]
        when :select_option then [select_line(step)]
        when :execute_script then [manual_comment(step)]
        when :assert_text then [assert_text_line(step)]
        when :assert_title then ["expect(page).to have_title(#{step.expected.inspect})"]
        when :wait_for, :assert_element then [presence_line(step.locator, step.condition)]
        when :assert_url then ["expect(page).to have_current_path(Regexp.new(#{step.expected.inspect}), url: true)"]
        else []
        end
      end

      def relative(url)
        uri = URI.parse(url)
        path = uri.path.to_s.empty? ? "/" : uri.path
        path += "?#{uri.query}" if uri.query
        path += "##{uri.fragment}" if uri.fragment
        path
      rescue URI::InvalidURIError
        url
      end

      # id/name locators become attribute selectors with the value in an escaped,
      # single-quoted CSS string so ids/names containing [ ] : ' \ etc. stay valid.
      # css strategy is a caller-supplied selector and is passed through verbatim.
      def css(locator)
        strategy, value = locator
        case strategy.to_s
        when "css" then value
        when "id" then "[id=#{css_quote(value)}]"
        when "name" then "[name=#{css_quote(value)}]"
        else value # rubocop:disable Lint/DuplicateBranch
        end
      end

      # Quotes a value as a single-quoted CSS string literal, escaping backslash and
      # apostrophe. The whole selector is later .inspect-ed for the Ruby source layer,
      # so both the CSS grammar and the Ruby string literal stay well-formed.
      def css_quote(value)
        escaped = value.to_s.gsub(/['\\]/) { |c| "\\#{c}" }
        "'#{escaped}'"
      end

      def finder(locator)
        strategy, value = locator
        case strategy.to_s
        when "xpath" then "find(:xpath, #{value.inspect})"
        when "link_text" then "find_link(#{value.inspect})"
        else "find(#{css(locator).inspect})"
        end
      end

      def click_line(step) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        el = step.element || {}
        text = el[:text].to_s
        if (el[:tag] == "button" || (el[:tag] == "input" && %w[submit button].include?(el[:type].to_s))) && !text.empty?
          "click_button #{text.inspect}"
        elsif el[:tag] == "a" && !text.empty?
          "click_link #{text.inspect}"
        else
          "#{finder(step.locator)}.click"
        end
      end

      # clear: true replays as replace (fill_in/set); clear: false replays as append
      # (send_keys), matching what Selenium actually did during the recording.
      def type_line(step)
        el = step.element || {}
        field = el[:name] || el[:id]
        value = step.masked ? 'ENV.fetch("SPEC_AI_PASSWORD")' : step.value.inspect
        if !step.clear
          "#{finder(step.locator)}.send_keys(#{value})"
        elsif field && %w[input textarea].include?(el[:tag])
          "fill_in #{field.inspect}, with: #{value}"
        else
          "#{finder(step.locator)}.set(#{value})"
        end
      end

      # Capybara's select matches option TEXT; a recording made via option value must
      # target the option node directly or the exported spec fails with ElementNotFound.
      def select_line(step)
        el = step.element || {}
        field = el[:name] || el[:id]
        if step.select_by == :value
          selector = "option[value=#{css_quote(step.value)}]"
          "#{finder(step.locator)}.find(#{selector.inspect}).select_option"
        elsif field
          "select #{step.value.inspect}, from: #{field.inspect}"
        else
          "#{finder(step.locator)}.select_option"
        end
      end

      # Dispatches by locator strategy (not the lossy css() fallback) so xpath/link_text
      # export as valid matchers. "present" and "gone" add visible: :all to match live
      # find_elements semantics (DOM presence/absence, hidden elements included);
      # only "visible" uses Capybara's visible-only default.
      def presence_line(locator, condition)
        matcher, arg = matcher_and_arg(locator, condition == "gone")
        suffix = condition == "visible" ? "" : ", visible: :all"
        "expect(page).to #{matcher}(#{arg}#{suffix})"
      end

      def matcher_and_arg(locator, negate)
        strategy, value = locator
        case strategy.to_s
        when "xpath" then [negate ? :have_no_xpath : :have_xpath, value.inspect]
        when "link_text" then [negate ? :have_no_link : :have_link, value.inspect]
        else [negate ? :have_no_css : :have_css, css(locator).inspect]
        end
      end

      def manual_comment(step)
        snippet = step.js.to_s.lines.first.to_s.strip[0, 60]
        "# MANUAL: review this step - execute_script recorded: #{snippet}"
      end

      def assert_text_line(step)
        if step.scope
          "expect(#{finder(step.scope)}).to have_content(#{step.expected.inspect})"
        else
          "expect(page).to have_content(#{step.expected.inspect})"
        end
      end
    end
  end
end
