# spec_ai - Design

**Date:** 2026-07-20
**Status:** Approved for planning
**Author:** Augustin Gottlieb (with Claude)

## Pitch

Explore with AI, keep real tests. `spec_ai` is a Ruby-native MCP server that lets Claude (or any MCP client) drive a browser through selenium-webdriver, records every action, and exports the session as a clean, runnable RSpec spec - plain selenium-webdriver or Capybara/Rails system spec format.

Playwright MCP has codegen for JS. This is the Ruby answer - built on Selenium by a Selenium committer.

## Goals

- Flagship community demo of the official MCP ruby-sdk (Anthropic + Shopify maintained).
- Generated specs run green on first try - locators are validated live during the session before they are exported.
- One-line install for Ruby devs; drops into Rails projects via Capybara system-spec export.
- Profile: visible to the AI/Claude Code community first, Ruby community second.

## Non-goals (v1)

Multi-session support, cookies/frames/alerts tools, BiDi introspection tools, page objects, Watir renderer, HTTP transport. All tracked as roadmap issues after launch.

## Architecture

```
spec_ai (gem)
├── exe/spec_ai              # entrypoint: stdio MCP server
├── lib/spec_ai/
│   ├── server.rb                  # MCP::Server (official ruby-sdk), registers tools
│   ├── browser_session.rb         # wraps Selenium::WebDriver - one active session
│   ├── tools/                     # one class per MCP tool, thin: validate → session call
│   ├── recorder.rb                # appends each action as IR step
│   └── codegen/
│       ├── rspec_renderer.rb      # IR → plain selenium-webdriver spec via ERB
│       ├── capybara_renderer.rb   # IR → Rails system spec via ERB
│       └── templates/
```

**Data flow:** MCP client calls tool → tool executes via `browser_session` → structured text result returned → successful action appended to `recorder` IR. `export_spec` folds IR into a runnable `*_spec.rb`.

**Key decisions:**

- **The IR is the heart.** Actions are recorded as data, not strings. Codegen is a pure function IR → Ruby source. Additional renderers (page objects, Watir) plug in later without touching recording. Fully testable without a browser.
- **One browser session at a time.**
- **stdio transport only** - what Claude Code, Claude Desktop, and Cursor use.
- **Runtime deps:** `selenium-webdriver` + official `mcp` gem only.
- **Ruby ≥ 3.2.**

Client config after `gem install spec_ai`: `command: spec_ai`.

## Tool surface (17 tools)

### Browser control (each successful call records to IR)

| Tool | Args | Returns |
|---|---|---|
| `start_browser` | browser (chrome/firefox/edge/safari), headless | session confirmation |
| `navigate` | url | title + current url |
| `snapshot` | - | compact DOM outline: interactive elements w/ suggested locators (id > name > css), text truncated, size-capped for token efficiency |
| `find_element` | locator strategy + value | element summary, or error with near-matches |
| `click` | locator | ok + resulting url/title |
| `type` | locator, text, clear: bool | ok |
| `select_option` | locator, value/text | ok |
| `screenshot` | - | image (base64) |
| `execute_script` | js | result (exported only as a `# MANUAL: review this step` comment) |
| `wait_for` | locator, condition (visible/present/gone), timeout | ok/timeout |
| `close_browser` | - | ok |

### Assertions (become `expect` lines in the export)

| Tool | Args |
|---|---|
| `assert_text` | text, optional locator scope |
| `assert_title` | expected |
| `assert_element` | locator, state (visible/present) |
| `assert_url` | pattern |

### Codegen

| Tool | Args | Returns |
|---|---|---|
| `export_spec` | description (spec name), format (`rspec` default \| `capybara`), path (optional) | generated `*_spec.rb` content + writes file |
| `reset_recording` | - | clears IR, keeps browser open |

**Notes:**

- `snapshot` is the driving-quality differentiator - the equivalent of Playwright MCP's accessibility snapshot, which mcp-selenium lacks.
- Assertions as explicit tools teach the agent to *test*, not just click. A session with no assertions exports with a `pending` warning comment.

## Recording + codegen

IR step example:

```ruby
{ action: :click, locator: [:id, "login-btn"], url_before: "/login",
  element: { tag: "button", text: "Log in", id: "login-btn", name: nil, type: "submit" },
  timestamp: ... }
{ action: :assert_text, expected: "Welcome back", scope: nil }
```

At click/type time the recorder stores element metadata (tag, text, name, id, type attr) - needed for idiomatic Capybara output.

### Renderer rules (both formats)

- v1 exports a single `it` block per spec; `description` arg names it.
- Failed actions are never recorded - only successful steps become code.
- Locators emitted exactly as used live, so generated specs run green first try.
- `execute_script` steps → `# MANUAL: review this step` comment.
- Text typed into `type="password"` fields is replaced with `ENV.fetch("SPEC_AI_PASSWORD")`. README warns about exporting real credentials.

### Plain RSpec format (`format: "rspec"`)

- `start_browser`/`close_browser` → `before`/`after` hooks with `Selenium::WebDriver.for`.
- Waits → explicit `wait.until` lines; never sleeps.

```ruby
require "selenium-webdriver"
require "rspec"

RSpec.describe "Login flow" do
  before do
    @driver = Selenium::WebDriver.for :chrome
    @wait = Selenium::WebDriver::Wait.new(timeout: 10)
  end

  after { @driver.quit }

  it "logs in successfully" do
    @driver.navigate.to "https://example.com/login"
    @driver.find_element(id: "email").send_keys "user@example.com"
    @driver.find_element(id: "password").send_keys ENV.fetch("SPEC_AI_PASSWORD")
    @driver.find_element(id: "login-btn").click
    @wait.until { @driver.find_element(css: ".welcome").displayed? }
    expect(@driver.find_element(css: ".welcome").text).to include("Welcome back")
  end
end
```

### Capybara format (`format: "capybara"`)

- Output is a Rails system spec (`type: :system`, `require "rails_helper"`).
- Idiomatic mapping via element metadata: input with matching id/name → `fill_in "email"`; button with text → `click_button "Log in"`; fallback `find(css)` otherwise.
- URLs become relative paths (`visit "/login"`) - base URL stripped, system specs run against the Rails test server.
- `wait_for` steps fold into auto-waiting Capybara matchers (`have_css`).
- Assertions → `expect(page).to have_content/have_css/have_current_path`.
- No driver setup/teardown - `rails_helper` owns it.

```ruby
require "rails_helper"

RSpec.describe "Login flow", type: :system do
  it "logs in successfully" do
    visit "/login"
    fill_in "email", with: "user@example.com"
    fill_in "password", with: ENV.fetch("SPEC_AI_PASSWORD")
    click_button "Log in"
    expect(page).to have_css(".welcome", text: "Welcome back")
  end
end
```

## Error handling

- Every tool wraps selenium exceptions into structured MCP error text, never stack traces. `NoSuchElementError` → "Element not found: css '.foo'. Did you mean: [up to 3 nearest candidates from last snapshot]". Recovery hints make agents self-correct.
- Failed actions are not recorded to IR.
- No session → every tool answers "No browser session. Call start_browser first."
- Driver crash / browser closed manually → session marked dead; next call explains and suggests `start_browser`; IR preserved so `export_spec` still works.
- `export_spec` with empty IR → error, not an empty file.
- Timeouts: default 10s, per-call override; timeout errors state which condition failed.

## Testing

This repo is a QA calling card - dogfood-grade.

- **Unit:** recorder + renderers as pure functions - IR in, exact Ruby source out (golden-file specs). No browser. Fast.
- **Tool layer:** tools tested against a fake session double - validates arg schemas and error mapping.
- **Integration:** real headless Chrome against local static fixture pages (`spec/fixtures/site/`), run in CI (GitHub Actions, ubuntu + chrome).
- **Meta-test (showpiece):** CI runs the exported spec from a scripted session and asserts it passes - proves the "generated specs run green" claim on every commit.
- RuboCop on the codebase **and** on generated output (style-checked in tests).

## Repo + launch

**Repo:** `github.com/aguspe/spec_ai`, MIT, public from day 1. Local: `~/code/spec_ai`.

**README structure:** pitch + 30-sec demo GIF → install + client config snippets → tool table → generated output examples in both formats → "why" (AI sessions are throwaway, tests are forever).

**Launch sequence:**

1. v0.1.0 on RubyGems + demo GIF in README
2. PR to modelcontextprotocol/servers community list + awesome-mcp-servers
3. Submit to Ruby Weekly / Short Ruby
4. nilcheck.dev article: "I built an MCP server in Ruby"
5. Mastodon (@aguspe@ruby.social) + LinkedIn
6. Conference talk material: "AI explores, you keep the tests"

**Success criteria:** one-line install works; generated specs pass green in CI meta-test; listed in MCP registries; 50+ stars in 3 months.

**Roadmap (post-v1, as good-first-issue bait):** multi-session, cookies/frames/alerts, BiDi tools, page objects renderer, Watir renderer, HTTP transport.
