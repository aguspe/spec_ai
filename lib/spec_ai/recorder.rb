# frozen_string_literal: true

module SpecAI
  Step = Struct.new(
    :action, :locator, :value, :url_before, :element, :expected, :scope,
    :masked, :condition, :timeout, :js, :select_by, :headless, :clear,
    keyword_init: true
  )

  class Recorder
    def initialize
      @steps = []
    end

    def record(**attrs)
      step = Step.new(**attrs)
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
