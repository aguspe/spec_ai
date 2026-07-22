# frozen_string_literal: true

RSpec.describe SpecAI::Codegen::RspecRenderer do
  def login_steps
    r = SpecAI::Recorder.new
    r.record(action: :start_browser, value: "chrome", headless: true)
    r.record(action: :navigate, value: "https://example.com/login")
    r.record(action: :type, locator: %w[id email], value: "user@example.com", clear: true,
             element: { tag: "input", text: "", id: "email", name: "email", type: "text" })
    r.record(action: :type, locator: %w[id password], masked: true, clear: true,
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
    steps = [SpecAI::Step.new(action: :navigate, value: "https://example.com")]
    out = described_class.render(steps: steps, description: "No asserts")
    expect(out).to include("# PENDING: no assertions were recorded in this session")
  end

  it "renders execute_script as a MANUAL comment" do
    steps = [SpecAI::Step.new(action: :execute_script, js: "window.scrollTo(0, 999)"),
             SpecAI::Step.new(action: :assert_title, expected: "Home")]
    out = described_class.render(steps: steps, description: "Scroll")
    expect(out).to include("# MANUAL: review this step - execute_script recorded: window.scrollTo(0, 999)")
    expect(out).to include('expect(@driver.title).to eq("Home")')
  end

  it "exports every assertion as a wait followed by the expect" do
    steps = [
      SpecAI::Step.new(action: :assert_text, expected: "Agustin"),
      SpecAI::Step.new(action: :assert_title, expected: "Store"),
      SpecAI::Step.new(action: :assert_element, locator: ["css", ".cart"], condition: "visible"),
      SpecAI::Step.new(action: :assert_url, expected: "cart")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include('@wait.until { @driver.find_element(tag_name: "body").text.include?("Agustin") }')
    expect(out).to include('@wait.until { @driver.title == "Store" }')
    expect(out).to include('@wait.until { @driver.find_element(css: ".cart").displayed? }')
    expect(out).to include('@wait.until { @driver.current_url.match?(Regexp.new("cart")) }')
    expect(out).to include("ignore: @ignored")
    expect(out).to include("Selenium::WebDriver::Error::NoSuchElementError")
  end

  it "warns and keeps the first browser when a recording has multiple sessions" do
    steps = [
      SpecAI::Step.new(action: :start_browser, value: "chrome", headless: true),
      SpecAI::Step.new(action: :navigate, value: "https://example.com"),
      SpecAI::Step.new(action: :start_browser, value: "firefox", headless: false),
      SpecAI::Step.new(action: :assert_title, expected: "x")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include("# WARNING: this recording has 2 browser sessions")
    expect(out).to include("Selenium::WebDriver.for :chrome")
  end

  it "produces lint-clean output for a warned recording with a long url" do
    long_url = "https://example.com/search?q=#{'x' * 160}"
    steps = [
      SpecAI::Step.new(action: :start_browser, value: "chrome", headless: true),
      SpecAI::Step.new(action: :navigate, value: long_url),
      SpecAI::Step.new(action: :start_browser, value: "firefox", headless: false),
      SpecAI::Step.new(action: :assert_title, expected: "x")
    ]
    out = described_class.render(steps: steps, description: "Long")
    expect(generated_lint_clean?(out)).to be(true), "generated RSpec output failed the generated-code lint config"
  end

  it "renders a screenshot step as a save_screenshot call, not a dropped line" do
    steps = [
      SpecAI::Step.new(action: :screenshot),
      SpecAI::Step.new(action: :screenshot),
      SpecAI::Step.new(action: :assert_title, expected: "x")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include('@driver.save_screenshot("screenshot-1.png")')
    expect(out).to include('@driver.save_screenshot("screenshot-2.png")')
  end

  it "renders non-headless start without options" do
    steps = [SpecAI::Step.new(action: :start_browser, value: "firefox", headless: false),
             SpecAI::Step.new(action: :assert_title, expected: "x")]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include("@driver = Selenium::WebDriver.for :firefox\n")
    expect(out).not_to include("options")
  end

  it "renders custom wait timeout inline and other actions correctly" do
    steps = [
      SpecAI::Step.new(action: :wait_for, locator: %w[name q], condition: "gone", timeout: 5),
      SpecAI::Step.new(action: :select_option, locator: %w[id country], value: "Denmark", select_by: :text),
      SpecAI::Step.new(action: :type, locator: %w[id email], value: "x", clear: true,
                       element: { tag: "input", id: "email", name: "email", type: "text", text: "" }),
      SpecAI::Step.new(action: :assert_element, locator: ["css", ".cart"], condition: "present"),
      SpecAI::Step.new(action: :assert_url, expected: "checkout/complete")
    ]
    out = described_class.render(steps: steps, description: "d")
    # rubocop:disable Layout/LineLength
    expect(out).to include('Selenium::WebDriver::Wait.new(timeout: 5, ignore: @ignored).until { @driver.find_elements(name: "q").empty? }')
    expect(out).to include('Selenium::WebDriver::Support::Select.new(@driver.find_element(id: "country")).select_by(:text, "Denmark")')
    # rubocop:enable Layout/LineLength
    expect(out).to include('@driver.find_element(id: "email").clear')
    expect(out).to include('expect(@driver.find_elements(css: ".cart").any?).to be true')
    expect(out).to include('expect(@driver.current_url).to match(Regexp.new("checkout/complete"))')
  end
end
