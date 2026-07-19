# selenium_spec Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship v0.1.0 of `selenium_spec` — a Ruby MCP server that drives a browser via selenium-webdriver, records every action, and exports the session as a runnable RSpec spec (plain selenium-webdriver or Capybara system-spec format).

**Architecture:** stdio MCP server built on the official `mcp` gem. 17 tool classes share one `App` (holds a single `BrowserSession` + `Recorder`). Successful tool calls append IR steps; two pure renderers turn IR into Ruby source via ERB templates. Codegen is fully testable without a browser (golden-file specs); real-browser integration + a CI meta-test prove exported specs run green.

**Tech Stack:** Ruby (dev on 4.0.2, floor 3.2), `mcp` gem (official ruby-sdk), `selenium-webdriver`, RSpec, RuboCop, GitHub Actions.

## Global Constraints

- Gem name: `selenium_spec`; module `SeleniumSpec`; version starts at `0.1.0`.
- `required_ruby_version = ">= 3.2"`. Develop with the PATH default Ruby (4.0.2 via chruby-style `~/.rubies`). All commands run from `~/code/selenium_spec`.
- Runtime dependencies ONLY: `mcp` (>= 0.4) and `selenium-webdriver` (>= 4.27). No Capybara dependency — the Capybara renderer only emits source text.
- stdio transport only. One browser session at a time.
- Failed actions are never recorded to IR. Only successful steps become spec code.
- Text typed into `type="password"` fields: real value is NOT stored in IR (`masked: true`, value nil); renderers emit `ENV.fetch("SELENIUM_SPEC_PASSWORD")`.
- Tool errors are returned as plain text starting with `ERROR: ` (deterministic across SDK versions; do not depend on an is_error response flag).
- Generated code must pass `rubocop --force-default-config --only Lint,Layout`.
- License MIT. Author: Augustin Gottlieb.
- Commit after every task (steps include exact commands). Conventional commit messages.

## File Structure

```
selenium_spec.gemspec
Gemfile
.rspec
.rubocop.yml
exe/selenium_spec
lib/selenium_spec.rb                        # requires everything
lib/selenium_spec/version.rb
lib/selenium_spec/errors.rb
lib/selenium_spec/recorder.rb               # Step struct + Recorder
lib/selenium_spec/browser_session.rb        # selenium-webdriver wrapper + snapshot JS
lib/selenium_spec/app.rb                    # session + recorder holder (server_context)
lib/selenium_spec/codegen/rspec_renderer.rb
lib/selenium_spec/codegen/capybara_renderer.rb
lib/selenium_spec/codegen/templates/rspec_spec.rb.erb
lib/selenium_spec/codegen/templates/capybara_spec.rb.erb
lib/selenium_spec/tools/helpers.rb          # shared response/error mapping + LOCATOR_PROPS
lib/selenium_spec/tools/session_tools.rb    # StartBrowser, CloseBrowser, Navigate
lib/selenium_spec/tools/interaction_tools.rb# FindElement, Click, Type, SelectOption, Screenshot, ExecuteScript, WaitFor
lib/selenium_spec/tools/snapshot_tool.rb    # Snapshot
lib/selenium_spec/tools/assertion_tools.rb  # AssertText, AssertTitle, AssertElement, AssertUrl
lib/selenium_spec/tools/codegen_tools.rb    # ExportSpec, ResetRecording
lib/selenium_spec/tools.rb                  # Tools::ALL registry
lib/selenium_spec/server.rb                 # MCP::Server wiring
spec/spec_helper.rb
spec/support/fake_session.rb
spec/selenium_spec/recorder_spec.rb
spec/selenium_spec/codegen/rspec_renderer_spec.rb
spec/selenium_spec/codegen/capybara_renderer_spec.rb
spec/selenium_spec/browser_session_spec.rb
spec/selenium_spec/tools/*_spec.rb
spec/selenium_spec/server_spec.rb
spec/fixtures/golden/login_flow_rspec.rb
spec/fixtures/golden/login_flow_capybara.rb
spec/fixtures/site/login.html
spec/integration/browser_session_integration_spec.rb   # tag :browser
spec/integration/meta_export_spec.rb                    # tag :browser — the showpiece
.github/workflows/ci.yml
README.md
```

Related-files rule: each tools file groups tools that share a test file and reviewer gate; renderers never require selenium-webdriver.

---

### Task 1: Gem skeleton

**Files:**
- Create: `selenium_spec.gemspec`, `Gemfile`, `.rspec`, `.rubocop.yml`, `lib/selenium_spec/version.rb`, `lib/selenium_spec.rb`, `spec/spec_helper.rb`, `spec/selenium_spec_spec.rb`, `.gitignore`

**Interfaces:**
- Produces: `SeleniumSpec::VERSION` (String `"0.1.0"`); `require "selenium_spec"` loads cleanly; `bundle exec rspec` and `bundle exec rubocop` both run green.

- [ ] **Step 1: Write files**

`lib/selenium_spec/version.rb`:

```ruby
# frozen_string_literal: true

module SeleniumSpec
  VERSION = "0.1.0"
end
```

`lib/selenium_spec.rb` (grows in later tasks; start minimal):

```ruby
# frozen_string_literal: true

require_relative "selenium_spec/version"

module SeleniumSpec
end
```

`selenium_spec.gemspec`:

```ruby
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
```

`Gemfile`:

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  gem "rake"
  gem "rspec", "~> 3.13"
  gem "rubocop", "~> 1.70"
  gem "rubocop-rspec", "~> 3.0"
end
```

`.rspec`:

```
--require spec_helper
--format documentation
```

`.rubocop.yml`:

```yaml
plugins:
  - rubocop-rspec

AllCops:
  TargetRubyVersion: 3.2
  NewCops: enable
  Exclude:
    - "spec/fixtures/**/*"
    - "vendor/**/*"

Style/Documentation:
  Enabled: false

Metrics/BlockLength:
  Exclude:
    - "spec/**/*"
    - "*.gemspec"

Metrics/MethodLength:
  Max: 25

Metrics/AbcSize:
  Max: 25

RSpec/ExampleLength:
  Max: 25

RSpec/MultipleExpectations:
  Max: 5
```

`spec/spec_helper.rb`:

```ruby
# frozen_string_literal: true

require "selenium_spec"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.order = :random
  Kernel.srand config.seed
  config.filter_run_excluding :browser unless ENV["BROWSER_TESTS"]
end
```

`spec/selenium_spec_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe SeleniumSpec do
  it "has a version number" do
    expect(SeleniumSpec::VERSION).to eq("0.1.0")
  end
end
```

`.gitignore`:

```
/.bundle/
/pkg/
/tmp/
Gemfile.lock
*.gem
```

- [ ] **Step 2: Install and run**

Run: `cd ~/code/selenium_spec && bundle install && bundle exec rspec`
Expected: `1 example, 0 failures`

- [ ] **Step 3: Lint**

Run: `bundle exec rubocop`
Expected: `no offenses detected`

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: gem skeleton with rspec + rubocop"
```

---

### Task 2: Recorder + Step IR

**Files:**
- Create: `lib/selenium_spec/recorder.rb`
- Modify: `lib/selenium_spec.rb` (add `require_relative "selenium_spec/recorder"`)
- Test: `spec/selenium_spec/recorder_spec.rb`

**Interfaces:**
- Produces: `SeleniumSpec::Step` — keyword-init Struct with members `action` (Symbol), `locator` (`[String strategy, String value]` or nil), `value`, `url_before`, `element` (Hash with symbol keys `:tag, :text, :id, :name, :type` or nil), `expected`, `scope` (locator pair or nil), `masked` (bool), `condition` (String), `timeout` (Integer), `js` (String), `select_by` (Symbol `:text`/`:value`), `headless` (bool), `clear` (bool).
- Produces: `SeleniumSpec::Recorder` — `#record(**attrs)` (appends Step, returns it), `#steps` (defensive copy Array<Step>), `#reset` (clears), `#empty?`, `#assertions?` (any step whose action starts with `assert_`).

- [ ] **Step 1: Write the failing test**

`spec/selenium_spec/recorder_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe SeleniumSpec::Recorder do
  subject(:recorder) { described_class.new }

  it "starts empty" do
    expect(recorder).to be_empty
  end

  it "records steps in order and returns copies" do
    recorder.record(action: :navigate, value: "https://example.com/login")
    recorder.record(action: :click, locator: %w[id login-btn],
                    element: { tag: "button", text: "Log in", id: "login-btn", name: nil, type: "submit" })
    steps = recorder.steps
    expect(steps.map(&:action)).to eq(%i[navigate click])
    steps.pop
    expect(recorder.steps.size).to eq(2)
  end

  it "reset clears all steps" do
    recorder.record(action: :navigate, value: "https://example.com")
    recorder.reset
    expect(recorder).to be_empty
  end

  it "detects assertions" do
    recorder.record(action: :click, locator: %w[id x])
    expect(recorder.assertions?).to be false
    recorder.record(action: :assert_text, expected: "Welcome")
    expect(recorder.assertions?).to be true
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/selenium_spec/recorder_spec.rb`
Expected: FAIL — `uninitialized constant SeleniumSpec::Recorder`

- [ ] **Step 3: Implement**

`lib/selenium_spec/recorder.rb`:

```ruby
# frozen_string_literal: true

module SeleniumSpec
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
```

Add to `lib/selenium_spec.rb` after the version require:

```ruby
require_relative "selenium_spec/recorder"
```

- [ ] **Step 4: Run tests + lint**

Run: `bundle exec rspec && bundle exec rubocop`
Expected: all pass, no offenses

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: Step IR and Recorder"
```

---

### Task 3: RSpec renderer (plain selenium-webdriver format)

**Files:**
- Create: `lib/selenium_spec/codegen/rspec_renderer.rb`, `lib/selenium_spec/codegen/templates/rspec_spec.rb.erb`, `spec/fixtures/golden/login_flow_rspec.rb`
- Modify: `lib/selenium_spec.rb` (add require)
- Test: `spec/selenium_spec/codegen/rspec_renderer_spec.rb`

**Interfaces:**
- Consumes: `SeleniumSpec::Step`, `SeleniumSpec::Recorder#steps`.
- Produces: `SeleniumSpec::Codegen::RspecRenderer.render(steps:, description:)` → String (complete spec file source). Later tasks call exactly this signature.

**Renderer rules (from spec):** `start_browser`/`close_browser`/`screenshot`/`find_element`/`snapshot` steps render no body lines (hooks/inspection). Headless start emits browser Options with `--headless=new` (chrome/edge) or `-headless` (firefox); safari ignores headless. Waits use `@wait.until` when timeout is 10, else inline `Selenium::WebDriver::Wait.new(timeout: N).until`. Missing assertions → `# PENDING: no assertions were recorded in this session` comment as first body line. `execute_script` → `# MANUAL: review this step — execute_script recorded: <first 60 chars>`.

- [ ] **Step 1: Write the golden file**

`spec/fixtures/golden/login_flow_rspec.rb`:

```ruby
require "selenium-webdriver"
require "rspec"

RSpec.describe "Login flow" do
  before do
    options = Selenium::WebDriver::Options.chrome
    options.add_argument("--headless=new")
    @driver = Selenium::WebDriver.for :chrome, options: options
    @wait = Selenium::WebDriver::Wait.new(timeout: 10)
  end

  after { @driver.quit }

  it "replays the recorded session" do
    @driver.navigate.to "https://example.com/login"
    @driver.find_element(id: "email").send_keys "user@example.com"
    @driver.find_element(id: "password").send_keys ENV.fetch("SELENIUM_SPEC_PASSWORD")
    @driver.find_element(id: "login-btn").click
    @wait.until { @driver.find_element(css: ".welcome").displayed? }
    expect(@driver.find_element(css: ".welcome").text).to include("Welcome back")
  end
end
```

- [ ] **Step 2: Write the failing test**

`spec/selenium_spec/codegen/rspec_renderer_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe SeleniumSpec::Codegen::RspecRenderer do
  def login_steps
    r = SeleniumSpec::Recorder.new
    r.record(action: :start_browser, value: "chrome", headless: true)
    r.record(action: :navigate, value: "https://example.com/login")
    r.record(action: :type, locator: %w[id email], value: "user@example.com",
             element: { tag: "input", text: "", id: "email", name: "email", type: "text" })
    r.record(action: :type, locator: %w[id password], masked: true,
             element: { tag: "input", text: "", id: "password", name: "password", type: "password" })
    r.record(action: :click, locator: %w[id login-btn],
             element: { tag: "button", text: "Log in", id: "login-btn", name: nil, type: "submit" })
    r.record(action: :wait_for, locator: ["css", ".welcome"], condition: "visible", timeout: 10)
    r.record(action: :assert_text, expected: "Welcome back", scope: ["css", ".welcome"])
    r.record(action: :close_browser)
    r.steps
  end

  it "renders the login flow exactly as the golden file" do
    golden = File.read("spec/fixtures/golden/login_flow_rspec.rb")
    expect(described_class.render(steps: login_steps, description: "Login flow")).to eq(golden)
  end

  it "adds a PENDING comment when no assertions were recorded" do
    steps = [SeleniumSpec::Step.new(action: :navigate, value: "https://example.com")]
    out = described_class.render(steps: steps, description: "No asserts")
    expect(out).to include("# PENDING: no assertions were recorded in this session")
  end

  it "renders execute_script as a MANUAL comment" do
    steps = [SeleniumSpec::Step.new(action: :execute_script, js: "window.scrollTo(0, 999)"),
             SeleniumSpec::Step.new(action: :assert_title, expected: "Home")]
    out = described_class.render(steps: steps, description: "Scroll")
    expect(out).to include("# MANUAL: review this step — execute_script recorded: window.scrollTo(0, 999)")
    expect(out).to include('expect(@driver.title).to eq("Home")')
  end

  it "renders non-headless start without options" do
    steps = [SeleniumSpec::Step.new(action: :start_browser, value: "firefox", headless: false),
             SeleniumSpec::Step.new(action: :assert_title, expected: "x")]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include("@driver = Selenium::WebDriver.for :firefox\n")
    expect(out).not_to include("options")
  end

  it "renders custom wait timeout inline and other actions correctly" do
    steps = [
      SeleniumSpec::Step.new(action: :wait_for, locator: %w[name q], condition: "gone", timeout: 5),
      SeleniumSpec::Step.new(action: :select_option, locator: %w[id country], value: "Denmark", select_by: :text),
      SeleniumSpec::Step.new(action: :type, locator: %w[id email], value: "x", clear: true,
                             element: { tag: "input", id: "email", name: "email", type: "text", text: "" }),
      SeleniumSpec::Step.new(action: :assert_element, locator: ["css", ".cart"], condition: "present"),
      SeleniumSpec::Step.new(action: :assert_url, expected: "checkout/complete")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include('Selenium::WebDriver::Wait.new(timeout: 5).until { @driver.find_elements(name: "q").empty? }')
    expect(out).to include('Selenium::WebDriver::Support::Select.new(@driver.find_element(id: "country")).select_by(:text, "Denmark")')
    expect(out).to include('@driver.find_element(id: "email").clear')
    expect(out).to include('expect(@driver.find_elements(css: ".cart").any?).to be true')
    expect(out).to include('expect(@driver.current_url).to match(Regexp.new("checkout/complete"))')
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/selenium_spec/codegen/rspec_renderer_spec.rb`
Expected: FAIL — `uninitialized constant SeleniumSpec::Codegen`

- [ ] **Step 4: Implement**

`lib/selenium_spec/codegen/templates/rspec_spec.rb.erb`:

```erb
require "selenium-webdriver"
require "rspec"

RSpec.describe <%= @description.inspect %> do
  before do
<% if headless? -%>
    options = Selenium::WebDriver::Options.<%= browser %>
    options.add_argument(<%= headless_flag.inspect %>)
    @driver = Selenium::WebDriver.for :<%= browser %>, options: options
<% else -%>
    @driver = Selenium::WebDriver.for :<%= browser %>
<% end -%>
    @wait = Selenium::WebDriver::Wait.new(timeout: 10)
  end

  after { @driver.quit }

  it "replays the recorded session" do
<% unless assertions? -%>
    # PENDING: no assertions were recorded in this session
<% end -%>
<% body_lines.each do |line| -%>
    <%= line %>
<% end -%>
  end
end
```

`lib/selenium_spec/codegen/rspec_renderer.rb`:

```ruby
# frozen_string_literal: true

require "erb"

module SeleniumSpec
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

      def lines_for(step) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength
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
        value = step.masked ? 'ENV.fetch("SELENIUM_SPEC_PASSWORD")' : step.value.inspect
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
        "# MANUAL: review this step — execute_script recorded: #{snippet}"
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
```

Add to `lib/selenium_spec.rb`:

```ruby
require_relative "selenium_spec/codegen/rspec_renderer"
```

- [ ] **Step 5: Run tests + lint**

Run: `bundle exec rspec && bundle exec rubocop`
Expected: all pass. If the golden comparison fails, diff the two strings and fix the RENDERER (never hand-tune the golden file to match broken output — the golden file is the contract from the design doc).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: RSpec renderer with golden-file spec"
```

---

### Task 4: Capybara renderer (Rails system-spec format)

**Files:**
- Create: `lib/selenium_spec/codegen/capybara_renderer.rb`, `lib/selenium_spec/codegen/templates/capybara_spec.rb.erb`, `spec/fixtures/golden/login_flow_capybara.rb`
- Modify: `lib/selenium_spec.rb` (add require)
- Test: `spec/selenium_spec/codegen/capybara_renderer_spec.rb`

**Interfaces:**
- Consumes: `SeleniumSpec::Step` (uses `element` metadata for idiomatic Capybara calls).
- Produces: `SeleniumSpec::Codegen::CapybaraRenderer.render(steps:, description:)` → String. Same signature as RspecRenderer — export tool switches on format.

**Mapping rules (from spec):** URLs → relative paths (`visit "/login"`). Element with matching name/id on input/textarea → `fill_in "name"`; button (or input[type=submit]) with text → `click_button "Log in"`; link with text → `click_link`; else `find(css)` fallback (`find(:xpath, ...)` for xpath locators). `wait_for` folds into `have_css`/`have_no_css`. No driver setup — `rails_helper` owns it. `start_browser`/`close_browser`/`screenshot`/`find_element`/`snapshot` render nothing.

- [ ] **Step 1: Write the golden file**

`spec/fixtures/golden/login_flow_capybara.rb`:

```ruby
require "rails_helper"

RSpec.describe "Login flow", type: :system do
  it "replays the recorded session" do
    visit "/login"
    fill_in "email", with: "user@example.com"
    fill_in "password", with: ENV.fetch("SELENIUM_SPEC_PASSWORD")
    click_button "Log in"
    expect(page).to have_css(".welcome")
    expect(find(".welcome")).to have_content("Welcome back")
  end
end
```

- [ ] **Step 2: Write the failing test**

`spec/selenium_spec/codegen/capybara_renderer_spec.rb` (reuse the exact `login_steps` helper from Task 3's spec — copy it in; specs must be independently runnable):

```ruby
# frozen_string_literal: true

RSpec.describe SeleniumSpec::Codegen::CapybaraRenderer do
  def login_steps
    r = SeleniumSpec::Recorder.new
    r.record(action: :start_browser, value: "chrome", headless: true)
    r.record(action: :navigate, value: "https://example.com/login")
    r.record(action: :type, locator: %w[id email], value: "user@example.com",
             element: { tag: "input", text: "", id: "email", name: "email", type: "text" })
    r.record(action: :type, locator: %w[id password], masked: true,
             element: { tag: "input", text: "", id: "password", name: "password", type: "password" })
    r.record(action: :click, locator: %w[id login-btn],
             element: { tag: "button", text: "Log in", id: "login-btn", name: nil, type: "submit" })
    r.record(action: :wait_for, locator: ["css", ".welcome"], condition: "visible", timeout: 10)
    r.record(action: :assert_text, expected: "Welcome back", scope: ["css", ".welcome"])
    r.record(action: :close_browser)
    r.steps
  end

  it "renders the login flow exactly as the golden file" do
    golden = File.read("spec/fixtures/golden/login_flow_capybara.rb")
    expect(described_class.render(steps: login_steps, description: "Login flow")).to eq(golden)
  end

  it "falls back to find(css).click when the element has no button/link identity" do
    steps = [SeleniumSpec::Step.new(action: :click, locator: ["css", ".card"],
                                    element: { tag: "div", text: "Open", id: nil, name: nil, type: nil }),
             SeleniumSpec::Step.new(action: :assert_title, expected: "x")]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include('find(".card").click')
  end

  it "maps remaining actions to idiomatic Capybara" do
    steps = [
      SeleniumSpec::Step.new(action: :click, locator: ["link_text", "Pricing"],
                             element: { tag: "a", text: "Pricing", id: nil, name: nil, type: nil }),
      SeleniumSpec::Step.new(action: :select_option, locator: %w[id country], value: "Denmark", select_by: :text,
                             element: { tag: "select", text: "", id: "country", name: "country", type: nil }),
      SeleniumSpec::Step.new(action: :wait_for, locator: ["css", ".spinner"], condition: "gone", timeout: 10),
      SeleniumSpec::Step.new(action: :assert_element, locator: %w[id cart], condition: "present"),
      SeleniumSpec::Step.new(action: :assert_url, expected: "checkout"),
      SeleniumSpec::Step.new(action: :assert_text, expected: "Done")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include('click_link "Pricing"')
    expect(out).to include('select "Denmark", from: "country"')
    expect(out).to include('expect(page).to have_no_css(".spinner")')
    expect(out).to include('expect(page).to have_css("#cart")')
    expect(out).to include('expect(page).to have_current_path(Regexp.new("checkout"), url: true)')
    expect(out).to include('expect(page).to have_content("Done")')
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/selenium_spec/codegen/capybara_renderer_spec.rb`
Expected: FAIL — `uninitialized constant SeleniumSpec::Codegen::CapybaraRenderer`

- [ ] **Step 4: Implement**

`lib/selenium_spec/codegen/templates/capybara_spec.rb.erb`:

```erb
require "rails_helper"

RSpec.describe <%= @description.inspect %>, type: :system do
  it "replays the recorded session" do
<% unless assertions? -%>
    # PENDING: no assertions were recorded in this session
<% end -%>
<% body_lines.each do |line| -%>
    <%= line %>
<% end -%>
  end
end
```

`lib/selenium_spec/codegen/capybara_renderer.rb`:

```ruby
# frozen_string_literal: true

require "erb"
require "uri"

module SeleniumSpec
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

      def body_lines
        @steps.flat_map { |step| lines_for(step) }
      end

      def lines_for(step) # rubocop:disable Metrics/CyclomaticComplexity
        case step.action
        when :navigate then ["visit #{relative(step.value).inspect}"]
        when :click then [click_line(step)]
        when :type then [type_line(step)]
        when :select_option then [select_line(step)]
        when :wait_for then [wait_line(step)]
        when :execute_script then [manual_comment(step)]
        when :assert_text then [assert_text_line(step)]
        when :assert_title then ["expect(page).to have_title(#{step.expected.inspect})"]
        when :assert_element then ["expect(page).to have_css(#{css(step.locator).inspect})"]
        when :assert_url then ["expect(page).to have_current_path(Regexp.new(#{step.expected.inspect}), url: true)"]
        else []
        end
      end

      def relative(url)
        uri = URI.parse(url)
        path = uri.path.to_s.empty? ? "/" : uri.path
        uri.query ? "#{path}?#{uri.query}" : path
      end

      def css(locator)
        strategy, value = locator
        case strategy.to_s
        when "css" then value
        when "id" then "##{value}"
        when "name" then "[name='#{value}']"
        else value
        end
      end

      def finder(locator)
        strategy, value = locator
        strategy.to_s == "xpath" ? "find(:xpath, #{value.inspect})" : "find(#{css(locator).inspect})"
      end

      def click_line(step)
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

      def type_line(step)
        el = step.element || {}
        field = el[:name] || el[:id]
        value = step.masked ? 'ENV.fetch("SELENIUM_SPEC_PASSWORD")' : step.value.inspect
        if field && %w[input textarea].include?(el[:tag])
          "fill_in #{field.inspect}, with: #{value}"
        else
          "#{finder(step.locator)}.set(#{value})"
        end
      end

      def select_line(step)
        el = step.element || {}
        field = el[:name] || el[:id]
        field ? "select #{step.value.inspect}, from: #{field.inspect}" : "#{finder(step.locator)}.select_option"
      end

      def wait_line(step)
        matcher = step.condition == "gone" ? "have_no_css" : "have_css"
        "expect(page).to #{matcher}(#{css(step.locator).inspect})"
      end

      def manual_comment(step)
        snippet = step.js.to_s.lines.first.to_s.strip[0, 60]
        "# MANUAL: review this step — execute_script recorded: #{snippet}"
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
```

Add to `lib/selenium_spec.rb`:

```ruby
require_relative "selenium_spec/codegen/capybara_renderer"
```

- [ ] **Step 5: Run tests + lint**

Run: `bundle exec rspec && bundle exec rubocop`
Expected: all pass. Same golden-file rule as Task 3: fix the renderer, never the golden file.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: Capybara system-spec renderer"
```

---

### Task 5: Errors + BrowserSession

**Files:**
- Create: `lib/selenium_spec/errors.rb`, `lib/selenium_spec/browser_session.rb`
- Modify: `lib/selenium_spec.rb` (requires)
- Test: `spec/selenium_spec/browser_session_spec.rb`

**Interfaces:**
- Produces error classes: `SeleniumSpec::Error < StandardError`; `SessionNotStartedError`; `SessionDeadError`; `EmptyRecordingError`; `ElementNotFoundError` (built with `new(locator, suggestions)` — message: `Element not found: id "x". Did you mean: ...` when suggestions non-empty).
- Produces `SeleniumSpec::BrowserSession`:
  - `initialize(driver_factory: nil)` — factory is `callable.(browser_name_string, headless_bool) → driver`; default builds a real `Selenium::WebDriver` with headless options.
  - `start(browser:, headless: true)`, `quit`, `alive?` (bool), `browser_name` (String).
  - `navigate(url)`, `current_url`, `title`.
  - `find(locator)` → Selenium element (raises `ElementNotFoundError` with suggestions from last snapshot).
  - `click(locator)` → element metadata Hash (captured BEFORE the click).
  - `type(locator, text, clear: false)` → metadata Hash. `password_field?(metadata)` → bool (`metadata[:type] == "password"`).
  - `select_option(locator, text: nil, value: nil)` → `[metadata, select_by_symbol, chosen_string]`.
  - `screenshot_base64` → String.
  - `execute_script(js)` → result.
  - `wait_for(locator, condition:, timeout: 10)` → true or raises `Selenium::WebDriver::Error::TimeoutError`.
  - `snapshot` → Array of Hashes with string keys `"tag","id","name","type","text","href"` (max 100 entries); also cached as `last_snapshot`.
  - `element_metadata(element)` → `{ tag:, text:, id:, name:, type: }` (text truncated to 60 chars; blank attrs → nil).
  - `suggestions_for(locator)` → Array<String> (max 3), fuzzy match of locator value against last_snapshot id/name/text.
  - All selenium calls that raise `InvalidSessionIdError` (or connection refusal) mark the session dead; any call without a live session raises `SessionNotStartedError` (never started) or `SessionDeadError` (was started, died).
- Constant `SeleniumSpec::BrowserSession::STRATEGIES = %w[id css xpath name link_text]` and `SNAPSHOT_JS` (String).

- [ ] **Step 1: Write the failing test**

`spec/selenium_spec/browser_session_spec.rb` — use a hand-rolled FakeDriver (no real browser):

```ruby
# frozen_string_literal: true

RSpec.describe SeleniumSpec::BrowserSession do
  let(:fake_element) do
    instance_double(Selenium::WebDriver::Element).tap do |el|
      allow(el).to receive_messages(tag_name: "button", text: "Log in", click: nil)
      allow(el).to receive(:attribute).with("id").and_return("login-btn")
      allow(el).to receive(:attribute).with("name").and_return(nil)
      allow(el).to receive(:attribute).with("type").and_return("submit")
    end
  end

  let(:fake_driver) do
    double("driver").tap do |d|
      allow(d).to receive_messages(quit: nil, current_url: "https://x.test/", title: "X")
      allow(d).to receive(:find_element).with({ id: "login-btn" }).and_return(fake_element)
    end
  end

  let(:session) { described_class.new(driver_factory: ->(_browser, _headless) { fake_driver }) }

  it "raises SessionNotStartedError before start" do
    expect { session.navigate("https://x.test") }.to raise_error(SeleniumSpec::SessionNotStartedError)
  end

  it "starts and reports alive" do
    session.start(browser: "chrome")
    expect(session).to be_alive
    expect(session.browser_name).to eq("chrome")
  end

  it "click returns element metadata captured before the click" do
    session.start(browser: "chrome")
    meta = session.click(%w[id login-btn])
    expect(meta).to eq(tag: "button", text: "Log in", id: "login-btn", name: nil, type: "submit")
  end

  it "wraps NoSuchElementError into ElementNotFoundError with suggestions" do
    session.start(browser: "chrome")
    allow(fake_driver).to receive(:find_element).with({ id: "missing" })
                                                .and_raise(Selenium::WebDriver::Error::NoSuchElementError)
    session.instance_variable_set(:@last_snapshot,
                                  [{ "tag" => "button", "id" => "login-btn", "name" => nil, "text" => "Log in" }])
    expect { session.find(%w[id missing]) }.to raise_error(SeleniumSpec::ElementNotFoundError, /Did you mean/)
  end

  it "marks session dead on InvalidSessionIdError and raises SessionDeadError afterwards" do
    session.start(browser: "chrome")
    allow(fake_driver).to receive(:current_url).and_raise(Selenium::WebDriver::Error::InvalidSessionIdError)
    expect { session.current_url }.to raise_error(SeleniumSpec::SessionDeadError)
    expect { session.title }.to raise_error(SeleniumSpec::SessionDeadError)
    expect(session).not_to be_alive
  end

  it "identifies password fields from metadata" do
    expect(session.password_field?(type: "password")).to be true
    expect(session.password_field?(type: "text")).to be false
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/selenium_spec/browser_session_spec.rb`
Expected: FAIL — `uninitialized constant SeleniumSpec::BrowserSession`

- [ ] **Step 3: Implement**

`lib/selenium_spec/errors.rb`:

```ruby
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
```

`lib/selenium_spec/browser_session.rb`:

```ruby
# frozen_string_literal: true

require "selenium-webdriver"

module SeleniumSpec
  class BrowserSession
    STRATEGIES = %w[id css xpath name link_text].freeze
    DEFAULT_TIMEOUT = 10
    HEADLESS_FLAGS = { "chrome" => "--headless=new", "edge" => "--headless=new", "firefox" => "-headless" }.freeze

    SNAPSHOT_JS = <<~JS
      const sel = "a, button, input, select, textarea, [role=button], h1, h2, h3";
      return Array.from(document.querySelectorAll(sel)).slice(0, 100).map((el) => ({
        tag: el.tagName.toLowerCase(),
        id: el.id || null,
        name: el.getAttribute("name"),
        type: el.getAttribute("type"),
        text: (el.innerText || el.value || "").trim().slice(0, 60),
        href: el.getAttribute("href")
      }));
    JS

    attr_reader :browser_name, :last_snapshot

    def initialize(driver_factory: nil)
      @driver_factory = driver_factory || method(:default_driver)
      @driver = nil
      @dead = false
      @last_snapshot = []
    end

    def start(browser:, headless: true)
      quit if alive?
      @browser_name = browser
      @driver = @driver_factory.call(browser, headless)
      @dead = false
      @last_snapshot = []
    end

    def quit
      @driver&.quit
    rescue Selenium::WebDriver::Error::WebDriverError
      nil
    ensure
      @driver = nil
      @dead = false
    end

    def alive?
      !@driver.nil? && !@dead
    end

    def navigate(url)
      guard { @driver.navigate.to(url) }
    end

    def current_url = guard { @driver.current_url }
    def title = guard { @driver.title }

    def find(locator)
      guard do
        strategy, value = locator
        @driver.find_element(strategy.to_sym => value)
      end
    rescue Selenium::WebDriver::Error::NoSuchElementError
      raise ElementNotFoundError.new(locator, suggestions_for(locator))
    end

    def click(locator)
      element = find(locator)
      metadata = element_metadata(element)
      guard { element.click }
      metadata
    end

    def type(locator, text, clear: false)
      element = find(locator)
      metadata = element_metadata(element)
      guard do
        element.clear if clear
        element.send_keys(text)
      end
      metadata
    end

    def select_option(locator, text: nil, value: nil)
      element = find(locator)
      metadata = element_metadata(element)
      select = Selenium::WebDriver::Support::Select.new(element)
      by, chosen = text ? [:text, text] : [:value, value]
      guard { select.select_by(by, chosen) }
      [metadata, by, chosen]
    end

    def screenshot_base64 = guard { @driver.screenshot_as(:base64) }
    def execute_script(js) = guard { @driver.execute_script(js) }

    def wait_for(locator, condition:, timeout: DEFAULT_TIMEOUT)
      strategy, value = locator
      by = { strategy.to_sym => value }
      guard do
        Selenium::WebDriver::Wait.new(timeout: timeout).until do
          case condition
          when "visible" then @driver.find_elements(**by).any? { |e| e.displayed? }
          when "present" then @driver.find_elements(**by).any?
          when "gone" then @driver.find_elements(**by).empty?
          end
        end
      end
      true
    end

    def snapshot
      @last_snapshot = guard { @driver.execute_script(SNAPSHOT_JS) } || []
    end

    def element_metadata(element)
      {
        tag: element.tag_name,
        text: element.text.to_s.strip[0, 60],
        id: presence(element.attribute("id")),
        name: presence(element.attribute("name")),
        type: presence(element.attribute("type"))
      }
    end

    def password_field?(metadata)
      metadata[:type] == "password"
    end

    def suggestions_for(locator)
      _, value = locator
      needle = value.to_s.downcase
      scored = @last_snapshot.select do |entry|
        haystack = [entry["id"], entry["name"], entry["text"]].compact.join(" ").downcase
        haystack.include?(needle)
      end
      pool = scored.empty? ? @last_snapshot.first(3) : scored.first(3)
      pool.map { |e| describe_entry(e) }
    end

    private

    def presence(str)
      str.nil? || str.empty? ? nil : str
    end

    def describe_entry(entry)
      locator = if entry["id"] then "id=#{entry['id']}"
                elsif entry["name"] then "name=#{entry['name']}"
                else "css=#{entry['tag']}"
                end
      %(#{entry['tag']} "#{entry['text']}" [#{locator}])
    end

    def guard
      raise SessionNotStartedError if @driver.nil?
      raise SessionDeadError if @dead

      yield
    rescue Selenium::WebDriver::Error::InvalidSessionIdError, Errno::ECONNREFUSED
      @dead = true
      raise SessionDeadError
    end

    def default_driver(browser, headless)
      options = Selenium::WebDriver::Options.send(browser)
      options.add_argument(HEADLESS_FLAGS[browser]) if headless && HEADLESS_FLAGS.key?(browser)
      Selenium::WebDriver.for(browser.to_sym, options: options)
    end
  end
end
```

Add to `lib/selenium_spec.rb` (order matters — errors before session):

```ruby
require_relative "selenium_spec/errors"
require_relative "selenium_spec/browser_session"
```

- [ ] **Step 4: Run tests + lint**

Run: `bundle exec rspec && bundle exec rubocop`
Expected: all pass. Note: `suggestions_for` contains a deliberate simple heuristic — if RuboCop flags the condition, simplify to `haystack.include?(needle)` only; the tests only require that a fuzzy match returns candidates.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: BrowserSession wrapper with error taxonomy and snapshot JS"
```

---

### Task 6: App, tool helpers, and session tools (start_browser, navigate, close_browser)

**Files:**
- Create: `lib/selenium_spec/app.rb`, `lib/selenium_spec/tools/helpers.rb`, `lib/selenium_spec/tools/session_tools.rb`, `spec/support/fake_session.rb`
- Modify: `lib/selenium_spec.rb` (requires)
- Test: `spec/selenium_spec/tools/session_tools_spec.rb`

**Interfaces:**
- Produces `SeleniumSpec::App` — `#session` (BrowserSession), `#recorder` (Recorder); `App.new(session: BrowserSession.new, recorder: Recorder.new)`.
- Produces `SeleniumSpec::Tools::LOCATOR_PROPS` — frozen Hash: `{ strategy: { type: "string", enum: STRATEGIES }, value: { type: "string" } }`.
- Produces `SeleniumSpec::Tools::Helpers` (extended by every tool class):
  - `app(server_context)` → `server_context.fetch(:app)`
  - `text(msg)` → `MCP::Tool::Response.new([{ type: "text", text: msg }])`
  - `error(msg)` → `text("ERROR: #{msg}")`
  - `guarded(server_context) { |app| ... }` — rescues and maps: `SessionNotStartedError` → "No browser session. Call start_browser first."; `SessionDeadError` → "Browser session lost (crashed or closed manually). Recording preserved — call start_browser to continue, or export_spec to keep what you have."; `ElementNotFoundError` → its own message; `Selenium::WebDriver::Error::TimeoutError` → "Timed out: <message>"; `Selenium::WebDriver::Error::InvalidSelectorError` → "Invalid selector: <message>"; `Selenium::WebDriver::Error::WebDriverError` → "WebDriver error: <message>". All via `error(...)`.
- Produces tool classes (all `< MCP::Tool`, all with `class << self; def call(...)` pattern):
  - `Tools::StartBrowser` — name `start_browser`, args: `browser` (enum chrome/firefox/edge/safari, default chrome), `headless` (boolean, default true). Starts session, records `action: :start_browser, value: browser, headless: headless`, replies "Started <browser> (headless: <bool>). Recording actions for spec export."
  - `Tools::Navigate` — name `navigate`, args: `url` (required). Records `action: :navigate, value: url`. Replies with title + current url.
  - `Tools::CloseBrowser` — name `close_browser`. Quits session, records `action: :close_browser`, replies "Browser closed. Recording preserved — call export_spec to generate your spec."
- Produces `spec/support/fake_session.rb` — `FakeSession` class implementing the full BrowserSession public interface with canned returns and a `calls` audit array (used by all tool specs; see code below).

- [ ] **Step 1: Write FakeSession support file**

`spec/support/fake_session.rb`:

```ruby
# frozen_string_literal: true

class FakeSession
  attr_reader :calls
  attr_accessor :alive, :raise_on_next

  def initialize
    @calls = []
    @alive = false
    @raise_on_next = nil
    @last_snapshot = []
  end

  def check!(name)
    @calls << name
    return unless @raise_on_next

    err = @raise_on_next
    @raise_on_next = nil
    raise err
  end

  def start(browser:, headless: true)
    check!(:start)
    @alive = true
    @browser = browser
    @headless = headless
  end

  def quit = (check!(:quit)
              @alive = false)
  def alive? = @alive
  def browser_name = @browser
  def navigate(url) = check!(:navigate)
  def current_url = (check!(:current_url)
                     "https://example.com/login")
  def title = (check!(:title)
               "Example Login")

  def metadata
    { tag: "button", text: "Log in", id: "login-btn", name: nil, type: "submit" }
  end

  def find(locator) = (check!(:find)
                       :element)
  def click(locator) = (check!(:click)
                        metadata)
  def type(locator, text, clear: false) = (check!(:type)
                                           metadata.merge(tag: "input", type: "text", text: ""))
  def select_option(locator, text: nil, value: nil) = (check!(:select)
                                                       [metadata, :text, text || value])
  def screenshot_base64 = (check!(:screenshot)
                           "aGVsbG8=")
  def execute_script(js) = (check!(:execute)
                            "ok")
  def wait_for(locator, condition:, timeout: 10) = (check!(:wait)
                                                    true)
  def snapshot = (check!(:snapshot)
                  [{ "tag" => "button", "id" => "login-btn", "name" => nil, "type" => "submit",
                     "text" => "Log in", "href" => nil }])
  def password_field?(meta) = meta[:type] == "password"
  def element_metadata(el) = metadata
  def suggestions_for(locator) = []
end
```

(If RuboCop rejects the endless-method-with-begin style above, rewrite those methods as ordinary 3-line `def ... end` methods — behavior is what matters: log the call, optionally raise, return the canned value.)

- [ ] **Step 2: Write the failing test**

`spec/selenium_spec/tools/session_tools_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe "session tools" do
  let(:session) { FakeSession.new }
  let(:app) { SeleniumSpec::App.new(session: session, recorder: SeleniumSpec::Recorder.new) }
  let(:ctx) { { app: app } }

  def response_text(response)
    response.content.first[:text]
  end

  it "start_browser starts the session and records the step" do
    res = SeleniumSpec::Tools::StartBrowser.call(browser: "chrome", headless: true, server_context: ctx)
    expect(response_text(res)).to include("Started chrome")
    step = app.recorder.steps.last
    expect(step.action).to eq(:start_browser)
    expect(step.value).to eq("chrome")
    expect(step.headless).to be true
  end

  it "navigate records and reports title and url" do
    session.alive = true
    res = SeleniumSpec::Tools::Navigate.call(url: "https://example.com/login", server_context: ctx)
    expect(response_text(res)).to include("Example Login").and include("https://example.com/login")
    expect(app.recorder.steps.last.action).to eq(:navigate)
  end

  it "navigate without a session returns the no-session error and records nothing" do
    session.raise_on_next = SeleniumSpec::SessionNotStartedError
    res = SeleniumSpec::Tools::Navigate.call(url: "https://x.test", server_context: ctx)
    expect(response_text(res)).to eq("ERROR: No browser session. Call start_browser first.")
    expect(app.recorder).to be_empty
  end

  it "close_browser quits and preserves the recording" do
    session.alive = true
    app.recorder.record(action: :navigate, value: "https://x.test")
    res = SeleniumSpec::Tools::CloseBrowser.call(server_context: ctx)
    expect(response_text(res)).to include("Recording preserved")
    expect(app.recorder.steps.map(&:action)).to eq(%i[navigate close_browser])
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/selenium_spec/tools/session_tools_spec.rb`
Expected: FAIL — `uninitialized constant SeleniumSpec::App`

- [ ] **Step 4: Implement**

`lib/selenium_spec/app.rb`:

```ruby
# frozen_string_literal: true

module SeleniumSpec
  class App
    attr_reader :session, :recorder

    def initialize(session: BrowserSession.new, recorder: Recorder.new)
      @session = session
      @recorder = recorder
    end
  end
end
```

`lib/selenium_spec/tools/helpers.rb`:

```ruby
# frozen_string_literal: true

require "mcp"

module SeleniumSpec
  module Tools
    LOCATOR_PROPS = {
      strategy: { type: "string", enum: BrowserSession::STRATEGIES },
      value: { type: "string" }
    }.freeze

    module Helpers
      def app(server_context)
        server_context.fetch(:app)
      end

      def text(msg)
        MCP::Tool::Response.new([{ type: "text", text: msg }])
      end

      def error(msg)
        text("ERROR: #{msg}")
      end

      def guarded(server_context)
        yield app(server_context)
      rescue SessionNotStartedError
        error("No browser session. Call start_browser first.")
      rescue SessionDeadError
        error("Browser session lost (crashed or closed manually). Recording preserved — " \
              "call start_browser to continue, or export_spec to keep what you have.")
      rescue ElementNotFoundError => e
        error(e.message)
      rescue Selenium::WebDriver::Error::TimeoutError => e
        error("Timed out: #{e.message}")
      rescue Selenium::WebDriver::Error::InvalidSelectorError => e
        error("Invalid selector: #{e.message}")
      rescue Selenium::WebDriver::Error::WebDriverError => e
        error("WebDriver error: #{e.message}")
      end
    end
  end
end
```

`lib/selenium_spec/tools/session_tools.rb`:

```ruby
# frozen_string_literal: true

module SeleniumSpec
  module Tools
    class StartBrowser < MCP::Tool
      extend Helpers
      tool_name "start_browser"
      description "Start a browser session. All subsequent actions are recorded for spec export."
      input_schema(
        properties: {
          browser: { type: "string", enum: %w[chrome firefox edge safari], default: "chrome" },
          headless: { type: "boolean", default: true }
        },
        required: []
      )

      class << self
        def call(browser: "chrome", headless: true, server_context:)
          guarded(server_context) do |app|
            app.session.start(browser: browser, headless: headless)
            app.recorder.record(action: :start_browser, value: browser, headless: headless)
            text("Started #{browser} (headless: #{headless}). Recording actions for spec export.")
          end
        end
      end
    end

    class Navigate < MCP::Tool
      extend Helpers
      tool_name "navigate"
      description "Navigate the browser to a URL."
      input_schema(properties: { url: { type: "string" } }, required: ["url"])

      class << self
        def call(url:, server_context:)
          guarded(server_context) do |app|
            app.session.navigate(url)
            app.recorder.record(action: :navigate, value: url)
            text("Now at: #{app.session.title} (#{app.session.current_url})")
          end
        end
      end
    end

    class CloseBrowser < MCP::Tool
      extend Helpers
      tool_name "close_browser"
      description "Close the browser. The recording is preserved for export_spec."
      input_schema(properties: {}, required: [])

      class << self
        def call(server_context:)
          guarded(server_context) do |app|
            app.session.quit
            app.recorder.record(action: :close_browser)
            text("Browser closed. Recording preserved — call export_spec to generate your spec.")
          end
        end
      end
    end
  end
end
```

Add to `lib/selenium_spec.rb`:

```ruby
require_relative "selenium_spec/app"
require_relative "selenium_spec/tools/helpers"
require_relative "selenium_spec/tools/session_tools"
```

Note: if the installed `mcp` gem version does not provide the `tool_name` DSL, check `bundle open mcp` — older versions derive the name from the class name; in that case keep the classes named as-is and set `tool_name` via whatever the gem's README documents. Do not silently ship tools with wrong names: the stdio smoke test in Task 10 asserts all 17 names.

- [ ] **Step 5: Run tests + lint**

Run: `bundle exec rspec && bundle exec rubocop`
Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: App context, tool helpers, session tools"
```

---

### Task 7: Interaction tools (find_element, click, type, select_option, screenshot, execute_script, wait_for)

**Files:**
- Create: `lib/selenium_spec/tools/interaction_tools.rb`
- Modify: `lib/selenium_spec.rb` (require)
- Test: `spec/selenium_spec/tools/interaction_tools_spec.rb`

**Interfaces:**
- Consumes: `Helpers`, `LOCATOR_PROPS`, `FakeSession`, `App`.
- Produces tools: `FindElement` (`find_element`), `Click` (`click`), `Type` (`type`), `SelectOption` (`select_option`), `Screenshot` (`screenshot`), `ExecuteScript` (`execute_script`), `WaitFor` (`wait_for`).
- Recording contract (used by renderers): `click` records `locator` + `element`; `type` records `locator`, `element`, `clear`, and either `value` (plain) or `masked: true` with `value: nil` (password field); `select_option` records `locator`, `element`, `value` (chosen), `select_by`; `wait_for` records `locator`, `condition`, `timeout`; `execute_script` records `js`; `find_element` and `screenshot` record bare steps (`action` + `locator` for find). Failed calls record nothing (guaranteed because `guarded` catches before `record`).

- [ ] **Step 1: Write the failing test**

`spec/selenium_spec/tools/interaction_tools_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe "interaction tools" do
  let(:session) { FakeSession.new }
  let(:app) { SeleniumSpec::App.new(session: session, recorder: SeleniumSpec::Recorder.new) }
  let(:ctx) { { app: app } }

  before { session.alive = true }

  def response_text(response)
    response.content.first[:text]
  end

  it "click records locator and element metadata" do
    res = SeleniumSpec::Tools::Click.call(strategy: "id", value: "login-btn", server_context: ctx)
    expect(response_text(res)).to include("Clicked id=login-btn")
    step = app.recorder.steps.last
    expect(step.action).to eq(:click)
    expect(step.locator).to eq(%w[id login-btn])
    expect(step.element[:tag]).to eq("button")
  end

  it "type records plain values" do
    SeleniumSpec::Tools::Type.call(strategy: "id", value: "email", text: "a@b.c", clear: true, server_context: ctx)
    step = app.recorder.steps.last
    expect(step.action).to eq(:type)
    expect(step.value).to eq("a@b.c")
    expect(step.clear).to be true
    expect(step.masked).to be_falsey
  end

  it "type masks password fields and never stores the value" do
    allow(session).to receive(:type).and_return({ tag: "input", type: "password", id: "password",
                                                  name: "password", text: "" })
    res = SeleniumSpec::Tools::Type.call(strategy: "id", value: "password", text: "hunter2", server_context: ctx)
    step = app.recorder.steps.last
    expect(step.masked).to be true
    expect(step.value).to be_nil
    expect(response_text(res)).to include("password field — value masked in recording")
    expect(app.recorder.steps.map(&:value)).not_to include("hunter2")
  end

  it "select_option records the chosen option and select_by" do
    SeleniumSpec::Tools::SelectOption.call(strategy: "id", value: "country", text: "Denmark", server_context: ctx)
    step = app.recorder.steps.last
    expect(step.action).to eq(:select_option)
    expect(step.value).to eq("Denmark")
    expect(step.select_by).to eq(:text)
  end

  it "wait_for records condition and timeout" do
    SeleniumSpec::Tools::WaitFor.call(strategy: "css", value: ".welcome", condition: "visible",
                                      timeout: 5, server_context: ctx)
    step = app.recorder.steps.last
    expect(step.condition).to eq("visible")
    expect(step.timeout).to eq(5)
  end

  it "wait_for timeout returns an error and records nothing" do
    session.raise_on_next = Selenium::WebDriver::Error::TimeoutError.new("timed out after 5 seconds")
    res = SeleniumSpec::Tools::WaitFor.call(strategy: "css", value: ".gone", condition: "visible",
                                            timeout: 5, server_context: ctx)
    expect(response_text(res)).to start_with("ERROR: Timed out")
    expect(app.recorder).to be_empty
  end

  it "screenshot returns an image content block" do
    res = SeleniumSpec::Tools::Screenshot.call(server_context: ctx)
    block = res.content.first
    expect(block[:type]).to eq("image")
    expect(block[:mimeType]).to eq("image/png")
    expect(block[:data]).to eq("aGVsbG8=")
  end

  it "execute_script records the js and flags it as manual" do
    res = SeleniumSpec::Tools::ExecuteScript.call(script: "return 1", server_context: ctx)
    expect(response_text(res)).to include("exported only as a MANUAL comment")
    expect(app.recorder.steps.last.js).to eq("return 1")
  end

  it "find_element reports the element without changing the page" do
    res = SeleniumSpec::Tools::FindElement.call(strategy: "id", value: "login-btn", server_context: ctx)
    expect(response_text(res)).to include("button")
    expect(app.recorder.steps.last.action).to eq(:find_element)
  end

  it "find_element surfaces ElementNotFoundError message with suggestions" do
    session.raise_on_next = SeleniumSpec::ElementNotFoundError.new(%w[id missing], ['button "Log in" [id=login-btn]'])
    res = SeleniumSpec::Tools::FindElement.call(strategy: "id", value: "missing", server_context: ctx)
    expect(response_text(res)).to include("ERROR: Element not found: id \"missing\". Did you mean")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/selenium_spec/tools/interaction_tools_spec.rb`
Expected: FAIL — `uninitialized constant SeleniumSpec::Tools::Click`

- [ ] **Step 3: Implement**

`lib/selenium_spec/tools/interaction_tools.rb`:

```ruby
# frozen_string_literal: true

module SeleniumSpec
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
            app.recorder.record(action: :click, locator: [strategy, value], element: meta)
            text("Clicked #{strategy}=#{value}. Now at: #{app.session.title} (#{app.session.current_url})")
          end
        end
      end
    end

    class Type < MCP::Tool
      extend Helpers
      tool_name "type"
      description "Type text into an element. Password fields are masked in the recording " \
                  "and exported as ENV.fetch(\"SELENIUM_SPEC_PASSWORD\")."
      input_schema(
        properties: LOCATOR_PROPS.merge(
          text: { type: "string" },
          clear: { type: "boolean", default: false }
        ),
        required: %w[strategy value text]
      )

      class << self
        def call(strategy:, value:, text:, clear: false, server_context:)
          guarded(server_context) do |app|
            meta = app.session.type([strategy, value], text, clear: clear)
            if app.session.password_field?(meta)
              app.recorder.record(action: :type, locator: [strategy, value], element: meta,
                                  masked: true, clear: clear)
              text("Typed into #{strategy}=#{value} (password field — value masked in recording).")
            else
              app.recorder.record(action: :type, locator: [strategy, value], element: meta,
                                  value: text, clear: clear)
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
        def call(strategy:, value:, text: nil, option_value: nil, server_context:)
          return error("Provide text or option_value.") if text.nil? && option_value.nil?

          guarded(server_context) do |app|
            meta, by, chosen = app.session.select_option([strategy, value], text: text, value: option_value)
            app.recorder.record(action: :select_option, locator: [strategy, value], element: meta,
                                value: chosen, select_by: by)
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
        def call(strategy:, value:, condition:, timeout: 10, server_context:)
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
```

Add to `lib/selenium_spec.rb`:

```ruby
require_relative "selenium_spec/tools/interaction_tools"
```

- [ ] **Step 4: Run tests + lint**

Run: `bundle exec rspec && bundle exec rubocop`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: interaction tools with password masking"
```

---

### Task 8: Snapshot tool

**Files:**
- Create: `lib/selenium_spec/tools/snapshot_tool.rb`
- Modify: `lib/selenium_spec.rb` (require)
- Test: `spec/selenium_spec/tools/snapshot_tool_spec.rb`

**Interfaces:**
- Consumes: `BrowserSession#snapshot` (Array of string-keyed Hashes).
- Produces `Tools::Snapshot` (`snapshot`): no args. Formats each entry as one line: `- <tag> "<text>" [locator: id=<id>]` (locator preference id > name > `no unique locator — inspect with find_element or use css/xpath`). Records `action: :snapshot`. Output capped: max 100 lines (session already caps), header line `Interactive elements (N):`.

- [ ] **Step 1: Write the failing test**

`spec/selenium_spec/tools/snapshot_tool_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe SeleniumSpec::Tools::Snapshot do
  let(:session) { FakeSession.new }
  let(:app) { SeleniumSpec::App.new(session: session, recorder: SeleniumSpec::Recorder.new) }
  let(:ctx) { { app: app } }

  before { session.alive = true }

  it "lists interactive elements with suggested locators" do
    allow(session).to receive(:snapshot).and_return(
      [
        { "tag" => "button", "id" => "login-btn", "name" => nil, "type" => "submit", "text" => "Log in", "href" => nil },
        { "tag" => "input", "id" => nil, "name" => "email", "type" => "text", "text" => "", "href" => nil },
        { "tag" => "h1", "id" => nil, "name" => nil, "type" => nil, "text" => "Welcome", "href" => nil }
      ]
    )
    res = described_class.call(server_context: ctx)
    out = res.content.first[:text]
    expect(out).to include("Interactive elements (3):")
    expect(out).to include('- button "Log in" [locator: id=login-btn]')
    expect(out).to include('- input "" [locator: name=email]')
    expect(out).to include('- h1 "Welcome" [no unique locator — inspect with find_element or use css/xpath]')
    expect(app.recorder.steps.last.action).to eq(:snapshot)
  end

  it "reports an empty page" do
    allow(session).to receive(:snapshot).and_return([])
    res = described_class.call(server_context: ctx)
    expect(res.content.first[:text]).to include("Interactive elements (0):")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/selenium_spec/tools/snapshot_tool_spec.rb`
Expected: FAIL — `uninitialized constant SeleniumSpec::Tools::Snapshot`

- [ ] **Step 3: Implement**

`lib/selenium_spec/tools/snapshot_tool.rb`:

```ruby
# frozen_string_literal: true

module SeleniumSpec
  module Tools
    class Snapshot < MCP::Tool
      extend Helpers
      tool_name "snapshot"
      description "Compact outline of interactive elements on the page with ready-to-use locators. " \
                  "Call this before interacting to pick reliable locators."
      input_schema(properties: {}, required: [])

      class << self
        def call(server_context:)
          guarded(server_context) do |app|
            entries = app.session.snapshot
            app.recorder.record(action: :snapshot)
            lines = entries.map { |e| format_entry(e) }
            text(["Interactive elements (#{entries.size}):", *lines].join("\n"))
          end
        end

        private

        def format_entry(entry)
          locator =
            if entry["id"] && !entry["id"].empty? then "locator: id=#{entry['id']}"
            elsif entry["name"] && !entry["name"].empty? then "locator: name=#{entry['name']}"
            else "no unique locator — inspect with find_element or use css/xpath"
            end
          %(- #{entry['tag']} "#{entry['text']}" [#{locator}])
        end
      end
    end
  end
end
```

Add to `lib/selenium_spec.rb`:

```ruby
require_relative "selenium_spec/tools/snapshot_tool"
```

- [ ] **Step 4: Run tests + lint**

Run: `bundle exec rspec && bundle exec rubocop`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: snapshot tool with locator suggestions"
```

---

### Task 9: Assertion tools

**Files:**
- Create: `lib/selenium_spec/tools/assertion_tools.rb`
- Modify: `lib/selenium_spec.rb` (require)
- Test: `spec/selenium_spec/tools/assertion_tools_spec.rb`

**Interfaces:**
- Produces tools: `AssertText` (`assert_text`: `text` required, optional `scope_strategy`/`scope_value`), `AssertTitle` (`assert_title`: `expected`), `AssertElement` (`assert_element`: locator + `state` enum visible/present), `AssertUrl` (`assert_url`: `pattern` — treated as a Ruby regexp source string).
- Behavior: each assertion is CHECKED live against the session. Pass → recorded (actions `:assert_text/:assert_title/:assert_element/:assert_url`, `expected` holds the expectation, `scope` holds scope locator pair, `condition` holds assert_element state) and replies "Assertion passed: ...". Fail → `ERROR: Assertion failed: <what was expected> — actual: <what was found>`, nothing recorded.
- Live checks via session: `assert_text` → `find(scope || ["css", "body"])` element's `.text.include?(text)` (for the default body scope use `execute_script("return document.body.innerText")` instead — simpler and avoids a body locator recording); `assert_title` → `title == expected`; `assert_element` → `wait_for(locator, condition: state, timeout: 2)` inside rescue; `assert_url` → `Regexp.new(pattern).match?(current_url)`.

- [ ] **Step 1: Write the failing test**

`spec/selenium_spec/tools/assertion_tools_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe "assertion tools" do
  let(:session) { FakeSession.new }
  let(:app) { SeleniumSpec::App.new(session: session, recorder: SeleniumSpec::Recorder.new) }
  let(:ctx) { { app: app } }

  before { session.alive = true }

  def response_text(response)
    response.content.first[:text]
  end

  it "assert_text passes against page text and records with nil scope" do
    allow(session).to receive(:execute_script).and_return("Welcome back, user")
    res = SeleniumSpec::Tools::AssertText.call(text: "Welcome back", server_context: ctx)
    expect(response_text(res)).to include("Assertion passed")
    step = app.recorder.steps.last
    expect(step.action).to eq(:assert_text)
    expect(step.expected).to eq("Welcome back")
    expect(step.scope).to be_nil
  end

  it "assert_text fails cleanly and records nothing" do
    allow(session).to receive(:execute_script).and_return("Nope")
    res = SeleniumSpec::Tools::AssertText.call(text: "Welcome back", server_context: ctx)
    expect(response_text(res)).to start_with("ERROR: Assertion failed")
    expect(app.recorder).to be_empty
  end

  it "assert_text with scope checks the scoped element" do
    element = double("el", text: "Welcome back")
    allow(session).to receive(:find).with(["css", ".welcome"]).and_return(element)
    SeleniumSpec::Tools::AssertText.call(text: "Welcome back", scope_strategy: "css",
                                         scope_value: ".welcome", server_context: ctx)
    expect(app.recorder.steps.last.scope).to eq(["css", ".welcome"])
  end

  it "assert_title compares exactly" do
    res = SeleniumSpec::Tools::AssertTitle.call(expected: "Example Login", server_context: ctx)
    expect(response_text(res)).to include("Assertion passed")
    res2 = SeleniumSpec::Tools::AssertTitle.call(expected: "Wrong", server_context: ctx)
    expect(response_text(res2)).to include('actual: "Example Login"')
  end

  it "assert_element records state under condition" do
    SeleniumSpec::Tools::AssertElement.call(strategy: "css", value: ".welcome", state: "visible",
                                            server_context: ctx)
    step = app.recorder.steps.last
    expect(step.action).to eq(:assert_element)
    expect(step.condition).to eq("visible")
  end

  it "assert_url matches pattern against current url" do
    res = SeleniumSpec::Tools::AssertUrl.call(pattern: "example\\.com/log", server_context: ctx)
    expect(response_text(res)).to include("Assertion passed")
    step = app.recorder.steps.last
    expect(step.expected).to eq("example\\.com/log")
  end

  it "assert_url rejects an invalid regexp" do
    res = SeleniumSpec::Tools::AssertUrl.call(pattern: "([", server_context: ctx)
    expect(response_text(res)).to start_with("ERROR: Invalid pattern")
    expect(app.recorder).to be_empty
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/selenium_spec/tools/assertion_tools_spec.rb`
Expected: FAIL — `uninitialized constant SeleniumSpec::Tools::AssertText`

- [ ] **Step 3: Implement**

`lib/selenium_spec/tools/assertion_tools.rb`:

```ruby
# frozen_string_literal: true

module SeleniumSpec
  module Tools
    class AssertText < MCP::Tool
      extend Helpers
      tool_name "assert_text"
      description "Assert text is present on the page (or within a scoped element). " \
                  "Passing assertions become expect(...) lines in the exported spec."
      input_schema(
        properties: {
          text: { type: "string" },
          scope_strategy: { type: "string", enum: BrowserSession::STRATEGIES },
          scope_value: { type: "string" }
        },
        required: ["text"]
      )

      class << self
        def call(text:, scope_strategy: nil, scope_value: nil, server_context:)
          guarded(server_context) do |app|
            scope = scope_strategy && scope_value ? [scope_strategy, scope_value] : nil
            actual = scope ? app.session.find(scope).text : app.session.execute_script("return document.body.innerText")
            if actual.to_s.include?(text)
              app.recorder.record(action: :assert_text, expected: text, scope: scope)
              text("Assertion passed: page contains #{text.inspect}.")
            else
              error("Assertion failed: expected #{text.inspect} — actual: #{actual.to_s[0, 200].inspect}")
            end
          end
        end
      end
    end

    class AssertTitle < MCP::Tool
      extend Helpers
      tool_name "assert_title"
      description "Assert the page title equals the expected string."
      input_schema(properties: { expected: { type: "string" } }, required: ["expected"])

      class << self
        def call(expected:, server_context:)
          guarded(server_context) do |app|
            actual = app.session.title
            if actual == expected
              app.recorder.record(action: :assert_title, expected: expected)
              text("Assertion passed: title is #{expected.inspect}.")
            else
              error("Assertion failed: expected title #{expected.inspect} — actual: #{actual.inspect}")
            end
          end
        end
      end
    end

    class AssertElement < MCP::Tool
      extend Helpers
      tool_name "assert_element"
      description "Assert an element is visible or present."
      input_schema(
        properties: LOCATOR_PROPS.merge(state: { type: "string", enum: %w[visible present] }),
        required: %w[strategy value state]
      )

      class << self
        def call(strategy:, value:, state:, server_context:)
          guarded(server_context) do |app|
            app.session.wait_for([strategy, value], condition: state, timeout: 2)
            app.recorder.record(action: :assert_element, locator: [strategy, value], condition: state)
            text("Assertion passed: #{strategy}=#{value} is #{state}.")
          rescue Selenium::WebDriver::Error::TimeoutError
            error("Assertion failed: expected #{strategy}=#{value} to be #{state} — it is not.")
          end
        end
      end
    end

    class AssertUrl < MCP::Tool
      extend Helpers
      tool_name "assert_url"
      description "Assert the current URL matches a Ruby regexp pattern (string)."
      input_schema(properties: { pattern: { type: "string" } }, required: ["pattern"])

      class << self
        def call(pattern:, server_context:)
          regexp = begin
            Regexp.new(pattern)
          rescue RegexpError => e
            return error("Invalid pattern: #{e.message}")
          end
          guarded(server_context) do |app|
            actual = app.session.current_url
            if regexp.match?(actual)
              app.recorder.record(action: :assert_url, expected: pattern)
              text("Assertion passed: url matches /#{pattern}/.")
            else
              error("Assertion failed: expected url to match /#{pattern}/ — actual: #{actual.inspect}")
            end
          end
        end
      end
    end
  end
end
```

Add to `lib/selenium_spec.rb`:

```ruby
require_relative "selenium_spec/tools/assertion_tools"
```

- [ ] **Step 4: Run tests + lint**

Run: `bundle exec rspec && bundle exec rubocop`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: live-checked assertion tools"
```

---

### Task 10: Codegen tools, tool registry, server wiring, executable + stdio smoke test

**Files:**
- Create: `lib/selenium_spec/tools/codegen_tools.rb`, `lib/selenium_spec/tools.rb`, `lib/selenium_spec/server.rb`, `exe/selenium_spec`
- Modify: `lib/selenium_spec.rb` (requires)
- Test: `spec/selenium_spec/tools/codegen_tools_spec.rb`, `spec/selenium_spec/server_spec.rb`

**Interfaces:**
- Produces `Tools::ExportSpec` (`export_spec`): args `description` (required), `format` (enum `rspec`/`capybara`, default `rspec`), `path` (optional file path). Empty recording → `ERROR: Nothing recorded yet — drive the browser first, then export.` Otherwise renders via the matching renderer, writes to `path` when given (creating parent dirs), and returns the full generated source in the response text (prefixed with `Spec written to <path>` when written).
- Produces `Tools::ResetRecording` (`reset_recording`): clears recorder, keeps session, replies "Recording cleared. Browser still open."
- Produces `SeleniumSpec::Tools::ALL` — frozen Array of exactly these 17 classes in this order: StartBrowser, Navigate, Snapshot, FindElement, Click, Type, SelectOption, Screenshot, ExecuteScript, WaitFor, CloseBrowser, AssertText, AssertTitle, AssertElement, AssertUrl, ExportSpec, ResetRecording.
- Produces `SeleniumSpec::Server.build(app: App.new)` → `MCP::Server` (name `"selenium_spec"`, version `SeleniumSpec::VERSION`, `tools: Tools::ALL`, `server_context: { app: app }`) and `SeleniumSpec::Server.run` (opens StdioTransport).
- Produces `exe/selenium_spec` executable.

- [ ] **Step 1: Write the failing tests**

`spec/selenium_spec/tools/codegen_tools_spec.rb`:

```ruby
# frozen_string_literal: true

require "tmpdir"

RSpec.describe "codegen tools" do
  let(:session) { FakeSession.new }
  let(:recorder) { SeleniumSpec::Recorder.new }
  let(:app) { SeleniumSpec::App.new(session: session, recorder: recorder) }
  let(:ctx) { { app: app } }

  def response_text(response)
    response.content.first[:text]
  end

  before do
    recorder.record(action: :start_browser, value: "chrome", headless: true)
    recorder.record(action: :navigate, value: "https://example.com/login")
    recorder.record(action: :assert_title, expected: "Example Login")
  end

  it "exports rspec format by default" do
    res = SeleniumSpec::Tools::ExportSpec.call(description: "Login flow", server_context: ctx)
    expect(response_text(res)).to include('RSpec.describe "Login flow" do')
    expect(response_text(res)).to include('require "selenium-webdriver"')
  end

  it "exports capybara format on request" do
    res = SeleniumSpec::Tools::ExportSpec.call(description: "Login flow", format: "capybara", server_context: ctx)
    expect(response_text(res)).to include("type: :system")
    expect(response_text(res)).to include('visit "/login"')
  end

  it "writes to a path when given" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "specs", "login_spec.rb")
      res = SeleniumSpec::Tools::ExportSpec.call(description: "Login flow", path: path, server_context: ctx)
      expect(File.read(path)).to include('RSpec.describe "Login flow" do')
      expect(response_text(res)).to include("Spec written to #{path}")
    end
  end

  it "refuses to export an empty recording" do
    recorder.reset
    res = SeleniumSpec::Tools::ExportSpec.call(description: "x", server_context: ctx)
    expect(response_text(res)).to eq("ERROR: Nothing recorded yet — drive the browser first, then export.")
  end

  it "reset_recording clears steps but not the session" do
    session.alive = true
    res = SeleniumSpec::Tools::ResetRecording.call(server_context: ctx)
    expect(response_text(res)).to include("Recording cleared")
    expect(recorder).to be_empty
    expect(session).to be_alive
  end
end
```

`spec/selenium_spec/server_spec.rb`:

```ruby
# frozen_string_literal: true

require "open3"
require "json"

RSpec.describe SeleniumSpec::Server do
  EXPECTED_TOOLS = %w[
    start_browser navigate snapshot find_element click type select_option screenshot
    execute_script wait_for close_browser assert_text assert_title assert_element
    assert_url export_spec reset_recording
  ].freeze

  it "registers exactly the 17 designed tools" do
    expect(SeleniumSpec::Tools::ALL.size).to eq(17)
  end

  it "builds an MCP server" do
    expect(described_class.build).to be_a(MCP::Server)
  end

  it "answers tools/list over stdio with all 17 tools" do
    requests = [
      { jsonrpc: "2.0", id: 1, method: "initialize",
        params: { protocolVersion: "2025-06-18", capabilities: {},
                  clientInfo: { name: "spec", version: "0" } } },
      { jsonrpc: "2.0", method: "notifications/initialized" },
      { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }
    ].map(&:to_json).join("\n")

    stdout, _stderr, status = Open3.capture3("ruby", "exe/selenium_spec", stdin_data: "#{requests}\n")
    expect(status.exitstatus).to eq(0).or be_nil
    tools_line = stdout.lines.map { |l| JSON.parse(l) rescue nil }.compact.find { |m| m["id"] == 2 }
    expect(tools_line).not_to be_nil, "no tools/list response in: #{stdout.inspect}"
    names = tools_line.dig("result", "tools").map { |t| t["name"] }
    expect(names).to match_array(EXPECTED_TOOLS)
  end
end
```

(Note: the stdio process exits when stdin closes; if `capture3` hangs, add `timeout: 15` handling by wrapping in `Timeout.timeout(15)` from the `timeout` stdlib.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/selenium_spec/tools/codegen_tools_spec.rb spec/selenium_spec/server_spec.rb`
Expected: FAIL — `uninitialized constant SeleniumSpec::Tools::ExportSpec`

- [ ] **Step 3: Implement**

`lib/selenium_spec/tools/codegen_tools.rb`:

```ruby
# frozen_string_literal: true

require "fileutils"

module SeleniumSpec
  module Tools
    class ExportSpec < MCP::Tool
      extend Helpers
      tool_name "export_spec"
      description "Export the recorded session as a runnable spec. " \
                  "format: rspec (plain selenium-webdriver, default) or capybara (Rails system spec)."
      input_schema(
        properties: {
          description: { type: "string", description: "Spec description, e.g. 'Login flow'" },
          format: { type: "string", enum: %w[rspec capybara], default: "rspec" },
          path: { type: "string", description: "Optional file path to write the spec to" }
        },
        required: ["description"]
      )

      RENDERERS = {
        "rspec" => Codegen::RspecRenderer,
        "capybara" => Codegen::CapybaraRenderer
      }.freeze

      class << self
        def call(description:, format: "rspec", path: nil, server_context:)
          app = app(server_context)
          return error("Nothing recorded yet — drive the browser first, then export.") if app.recorder.empty?

          source = RENDERERS.fetch(format).render(steps: app.recorder.steps, description: description)
          if path
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, source)
            text("Spec written to #{path}\n\n#{source}")
          else
            text(source)
          end
        end
      end
    end

    class ResetRecording < MCP::Tool
      extend Helpers
      tool_name "reset_recording"
      description "Clear the recorded steps. The browser stays open."
      input_schema(properties: {}, required: [])

      class << self
        def call(server_context:)
          app(server_context).recorder.reset
          text("Recording cleared. Browser still open.")
        end
      end
    end
  end
end
```

`lib/selenium_spec/tools.rb`:

```ruby
# frozen_string_literal: true

module SeleniumSpec
  module Tools
    ALL = [
      StartBrowser, Navigate, Snapshot, FindElement, Click, Type, SelectOption,
      Screenshot, ExecuteScript, WaitFor, CloseBrowser,
      AssertText, AssertTitle, AssertElement, AssertUrl,
      ExportSpec, ResetRecording
    ].freeze
  end
end
```

`lib/selenium_spec/server.rb`:

```ruby
# frozen_string_literal: true

require "mcp"

module SeleniumSpec
  class Server
    def self.build(app: App.new)
      MCP::Server.new(
        name: "selenium_spec",
        version: SeleniumSpec::VERSION,
        tools: Tools::ALL,
        server_context: { app: app }
      )
    end

    def self.run
      transport = MCP::Server::Transports::StdioTransport.new(build)
      transport.open
    end
  end
end
```

`exe/selenium_spec`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "selenium_spec"

SeleniumSpec::Server.run
```

Run `chmod +x exe/selenium_spec`.

Final require block in `lib/selenium_spec.rb` (full file for reference):

```ruby
# frozen_string_literal: true

require_relative "selenium_spec/version"
require_relative "selenium_spec/errors"
require_relative "selenium_spec/recorder"
require_relative "selenium_spec/browser_session"
require_relative "selenium_spec/app"
require_relative "selenium_spec/codegen/rspec_renderer"
require_relative "selenium_spec/codegen/capybara_renderer"
require_relative "selenium_spec/tools/helpers"
require_relative "selenium_spec/tools/session_tools"
require_relative "selenium_spec/tools/interaction_tools"
require_relative "selenium_spec/tools/snapshot_tool"
require_relative "selenium_spec/tools/assertion_tools"
require_relative "selenium_spec/tools/codegen_tools"
require_relative "selenium_spec/tools"
require_relative "selenium_spec/server"

module SeleniumSpec
end
```

- [ ] **Step 4: Run tests + lint**

Run: `bundle exec rspec && bundle exec rubocop`
Expected: all pass — including the stdio smoke test proving all 17 tool names over JSON-RPC.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: export tools, server wiring, stdio executable"
```

---

### Task 11: Integration + meta-test (real headless Chrome)

**Files:**
- Create: `spec/fixtures/site/login.html`, `spec/integration/browser_session_integration_spec.rb`, `spec/integration/meta_export_spec.rb`

**Interfaces:**
- Consumes: everything. Tagged `:browser`; excluded unless `BROWSER_TESTS=1` (already configured in spec_helper).
- Produces: proof that (a) BrowserSession drives real Chrome, (b) a full tool-driven session exports a spec that PASSES when run by a fresh rspec process, and (c) generated code passes `rubocop --force-default-config --only Lint,Layout`.

- [ ] **Step 1: Write the fixture page**

`spec/fixtures/site/login.html`:

```html
<!doctype html>
<html>
<head><title>Fixture Login</title></head>
<body>
<h1>Login</h1>
<form id="login-form">
  <label>Email <input id="email" name="email" type="text"></label>
  <label>Password <input id="password" name="password" type="password"></label>
  <button id="login-btn" type="submit">Log in</button>
</form>
<div class="welcome" hidden>Welcome back</div>
<script>
document.getElementById("login-form").addEventListener("submit", function (e) {
  e.preventDefault();
  var email = document.getElementById("email").value;
  var password = document.getElementById("password").value;
  if (email && password) {
    setTimeout(function () { document.querySelector(".welcome").hidden = false; }, 300);
  }
});
</script>
</body>
</html>
```

- [ ] **Step 2: Write the integration spec**

`spec/integration/browser_session_integration_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe SeleniumSpec::BrowserSession, :browser do
  subject(:session) { described_class.new }

  let(:fixture_url) { "file://#{File.expand_path('../fixtures/site/login.html', __dir__)}" }

  after { session.quit }

  it "drives a real headless chrome through the login flow" do
    session.start(browser: "chrome", headless: true)
    session.navigate(fixture_url)
    expect(session.title).to eq("Fixture Login")

    entries = session.snapshot
    ids = entries.map { |e| e["id"] }
    expect(ids).to include("email", "password", "login-btn")

    session.type(%w[id email], "user@example.com")
    meta = session.type(%w[id password], "secret123")
    expect(session.password_field?(meta)).to be true

    click_meta = session.click(%w[id login-btn])
    expect(click_meta[:text]).to eq("Log in")

    expect(session.wait_for(["css", ".welcome"], condition: "visible", timeout: 5)).to be true
    expect(session.find(["css", ".welcome"]).text).to eq("Welcome back")
  end

  it "raises ElementNotFoundError with snapshot suggestions" do
    session.start(browser: "chrome", headless: true)
    session.navigate(fixture_url)
    session.snapshot
    expect { session.find(%w[id login]) }
      .to raise_error(SeleniumSpec::ElementNotFoundError, /Did you mean/)
  end
end
```

- [ ] **Step 3: Write the meta-test (the showpiece)**

`spec/integration/meta_export_spec.rb`:

```ruby
# frozen_string_literal: true

require "tmpdir"
require "open3"

RSpec.describe "exported spec runs green", :browser do
  let(:fixture_url) { "file://#{File.expand_path('../fixtures/site/login.html', __dir__)}" }
  let(:app) { SeleniumSpec::App.new }
  let(:ctx) { { app: app } }

  def call(tool, **args)
    tool.call(**args, server_context: ctx)
  end

  it "drives the tools end-to-end, exports, and the generated spec passes" do
    call(SeleniumSpec::Tools::StartBrowser, browser: "chrome", headless: true)
    call(SeleniumSpec::Tools::Navigate, url: fixture_url)
    call(SeleniumSpec::Tools::Type, strategy: "id", value: "email", text: "user@example.com")
    call(SeleniumSpec::Tools::Type, strategy: "id", value: "password", text: "secret123")
    call(SeleniumSpec::Tools::Click, strategy: "id", value: "login-btn")
    call(SeleniumSpec::Tools::WaitFor, strategy: "css", value: ".welcome", condition: "visible", timeout: 5)
    call(SeleniumSpec::Tools::AssertText, text: "Welcome back", scope_strategy: "css", scope_value: ".welcome")
    call(SeleniumSpec::Tools::CloseBrowser)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "login_flow_spec.rb")
      call(SeleniumSpec::Tools::ExportSpec, description: "Login flow", path: path)
      source = File.read(path)
      expect(source).to include('ENV.fetch("SELENIUM_SPEC_PASSWORD")')
      expect(source).not_to include("secret123")

      lint_out, lint_status = Open3.capture2e(
        "bundle", "exec", "rubocop", "--force-default-config", "--only", "Lint,Layout", path
      )
      expect(lint_status).to be_success, "generated code failed rubocop:\n#{lint_out}"

      run_out, run_status = Open3.capture2e(
        { "SELENIUM_SPEC_PASSWORD" => "secret123" },
        "bundle", "exec", "rspec", path
      )
      expect(run_status).to be_success, "generated spec failed:\n#{run_out}"
    end
  end
end
```

- [ ] **Step 4: Run browser tests locally**

Run: `BROWSER_TESTS=1 bundle exec rspec spec/integration --format documentation`
Expected: 3 examples, 0 failures (requires Chrome installed — present on this Mac). If the meta-test fails, debug the renderer/tools — NOT the meta-test. This test is the product claim.

- [ ] **Step 5: Run full suite + lint**

Run: `BROWSER_TESTS=1 bundle exec rspec && bundle exec rubocop`
Expected: all green

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "test: real-browser integration and green-export meta-test"
```

---

### Task 12: CI, README, LICENSE, release prep

**Files:**
- Create: `.github/workflows/ci.yml`, `README.md`, `LICENSE.txt`, `Rakefile`, `CHANGELOG.md`

**Interfaces:**
- Consumes: full test suite, `BROWSER_TESTS` env switch.
- Produces: CI matrix (Ruby 3.2 + 3.4, Chrome installed, full suite incl. browser + meta tests), README per spec's launch section, MIT license, `rake build` for gem packaging.

- [ ] **Step 1: Write CI workflow**

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.4"
          bundler-cache: true
      - run: bundle exec rubocop

  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        ruby: ["3.2", "3.4"]
    steps:
      - uses: actions/checkout@v4
      - uses: browser-actions/setup-chrome@v1
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true
      - name: Unit + integration + meta-test
        run: bundle exec rspec
        env:
          BROWSER_TESTS: "1"
```

- [ ] **Step 2: Write LICENSE.txt (MIT, copyright 2026 Augustin Gottlieb), Rakefile, CHANGELOG**

`Rakefile`:

```ruby
# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)
task default: :spec
```

`CHANGELOG.md`:

```markdown
# Changelog

## 0.1.0 — Unreleased

- Initial release: 17-tool MCP server driving selenium-webdriver.
- Session recording (IR) with password masking.
- Spec export: plain RSpec + selenium-webdriver, or Capybara Rails system spec.
- Snapshot tool with locator suggestions; live-checked assertion tools.
```

- [ ] **Step 3: Write README.md**

Follow the spec's README structure exactly (pitch → demo GIF placeholder → install + MCP client config → tool table → both output examples → "why"). Copy the tool table from the design doc (`docs/superpowers/specs/2026-07-20-selenium-spec-design.md`) and the two golden files as the output examples. Include Claude Code config:

````markdown
# selenium_spec

**Explore with AI, keep real tests.**

A Ruby-native MCP server: Claude drives your browser through selenium-webdriver, every
action is recorded, and the session exports as a clean, runnable RSpec spec — plain
selenium-webdriver or a Capybara Rails system spec. Built on the official
[MCP Ruby SDK](https://github.com/modelcontextprotocol/ruby-sdk).

> Playwright MCP has codegen for JS. This is the Ruby answer — built on Selenium by a
> Selenium committer.

*(demo GIF here)*

## Install

```bash
gem install selenium_spec
```

### Claude Code

```bash
claude mcp add selenium-spec -- selenium_spec
```

### Claude Desktop / Cursor

```json
{
  "mcpServers": {
    "selenium-spec": { "command": "selenium_spec" }
  }
}
```

## Tools

(table from design doc)

## What you get back

(the two golden-file examples, side by side)

## Why

AI browsing sessions are throwaway. Tests are forever. `selenium_spec` records every
action Claude takes with locators that were already validated live against the page —
so the exported spec runs green on the first try. Passwords are never stored: fields
of `type="password"` export as `ENV.fetch("SELENIUM_SPEC_PASSWORD")`.

Every commit runs a meta-test in CI: a scripted session exports a spec and CI asserts
the generated spec passes. The "runs green" claim is enforced, not promised.
````

- [ ] **Step 4: Full local verification**

Run: `BROWSER_TESTS=1 bundle exec rspec && bundle exec rubocop && gem build selenium_spec.gemspec`
Expected: suite green, no offenses, `selenium_spec-0.1.0.gem` built. Delete the built .gem afterwards (`rm selenium_spec-0.1.0.gem`).

- [ ] **Step 5: Commit and push**

```bash
git add -A && git commit -m "chore: CI, README, license, release prep"
```

Then create the GitHub repo and push (user confirmed public from day 1):

```bash
gh repo create aguspe/selenium_spec --public --source . --push --description "MCP server that drives Selenium and exports the session as runnable RSpec specs"
```

Verify CI passes on GitHub before any release step. RubyGems publish (`gem push`) is a HUMAN step — Augustin runs it (MFA required); do not attempt it from an agent.

---

## Post-plan launch checklist (not agent tasks — tracked for Augustin)

1. Record demo GIF, replace README placeholder.
2. `gem push selenium_spec-0.1.0.gem` (MFA).
3. PR to modelcontextprotocol/servers community list + awesome-mcp-servers.
4. Ruby Weekly / Short Ruby submission; nilcheck.dev article; Mastodon + LinkedIn.
5. Open roadmap issues labeled `good first issue`: multi-session, cookies/frames/alerts, BiDi tools, page-objects renderer, Watir renderer, HTTP transport.
