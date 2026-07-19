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
    # rubocop:disable Layout/LineLength
    expect(out).to include('Selenium::WebDriver::Wait.new(timeout: 5).until { @driver.find_elements(name: "q").empty? }')
    expect(out).to include('Selenium::WebDriver::Support::Select.new(@driver.find_element(id: "country")).select_by(:text, "Denmark")')
    # rubocop:enable Layout/LineLength
    expect(out).to include('@driver.find_element(id: "email").clear')
    expect(out).to include('expect(@driver.find_elements(css: ".cart").any?).to be true')
    expect(out).to include('expect(@driver.current_url).to match(Regexp.new("checkout/complete"))')
  end
end
