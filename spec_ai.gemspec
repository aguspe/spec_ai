# frozen_string_literal: true

require_relative "lib/spec_ai/version"

Gem::Specification.new do |spec|
  spec.name = "spec_ai"
  spec.version = SpecAI::VERSION
  spec.authors = ["Augustin Gottlieb"]
  spec.summary = "MCP server that drives Selenium and exports the session as runnable RSpec or Capybara specs"
  spec.description = "Explore with AI, keep real tests. A Ruby-native MCP server: Claude drives the browser through selenium-webdriver, every action is recorded, and the session exports as a clean RSpec or Capybara system spec."
  spec.homepage = "https://github.com/aguspe/spec_ai"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*", "exe/*", "README.md", "LICENSE.txt"]
  spec.bindir = "exe"
  spec.executables = ["spec_ai"]
  spec.require_paths = ["lib"]

  spec.add_dependency "mcp", ">= 0.25"
  spec.add_dependency "selenium-webdriver", ">= 4.27"
  spec.metadata["rubygems_mfa_required"] = "true"
end
