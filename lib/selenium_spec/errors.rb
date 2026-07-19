# frozen_string_literal: true

module SeleniumSpec
  class Error < StandardError; end
  class SessionNotStartedError < Error; end
  class SessionDeadError < Error; end
  class EmptyRecordingError < Error; end

  class ElementNotFoundError < Error
    def initialize(locator, suggestions = [])
      strategy, value = locator
      msg = "Element not found: #{strategy} #{value.inspect}."
      msg += " Did you mean: #{suggestions.join('; ')}" unless suggestions.empty?
      super(msg)
    end
  end
end
