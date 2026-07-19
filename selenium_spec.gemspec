# frozen_string_literal: true

require_relative "lib/selenium_spec/version"

Gem::Specification.new do |spec|
  spec.name = "selenium_spec"
  spec.version = SeleniumSpec::VERSION
  spec.authors = ["Augustin Gottlieb"]
  spec.summary = "MCP server that drives Selenium and exports the session as runnable RSpec specs"
  spec.description = "Explore with AI, keep real tests. A Ruby-native MCP server: Claude drives the browser through selenium-webdriver, every action is recorded, and the session exports as a clean RSpec or Capybara system spec."
  spec.homepage = "https://github.com/aguspe/selenium_spec"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*", "exe/*", "README.md", "LICENSE.txt"]
  spec.bindir = "exe"
  spec.executables = ["selenium_spec"]
  spec.require_paths = ["lib"]

  spec.add_dependency "mcp", ">= 0.4"
  spec.add_dependency "selenium-webdriver", ">= 4.27"
  spec.metadata["rubygems_mfa_required"] = "true"
end
