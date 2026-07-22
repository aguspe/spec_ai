# frozen_string_literal: true

module SpecAI
  Step = Struct.new(
    :action, :locator, :value, :element, :expected, :scope,
    :masked, :condition, :timeout, :js, :select_by, :headless, :clear, :unique,
    keyword_init: true
  )

  class Recorder
    def initialize
      @steps = []
    end

    # Steps are frozen once recorded: renderers and tools consume them read-only,
    # and a consumer mutating a Step would silently corrupt the recording.
    def record(**attrs)
      step = Step.new(**attrs).freeze
      @steps << step
      step
    end

    def steps
      @steps.dup
    end

    def reset
      @steps.clear
    end

    def empty?
      @steps.empty?
    end

    def assertions?
      @steps.any? { |s| s.action.to_s.start_with?("assert_") }
    end
  end
end
