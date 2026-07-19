# frozen_string_literal: true

require "spec_ai"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.order = :random
  Kernel.srand config.seed
  config.filter_run_excluding :browser unless ENV["BROWSER_TESTS"]
end
