# frozen_string_literal: true

RSpec.describe SpecAI::Codegen::CapybaraRenderer do
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
    golden = File.read("spec/fixtures/golden/login_flow_capybara.rb")
    expect(described_class.render(steps: login_steps, description: "Login flow")).to eq(golden)
  end

  it "falls back to find(css).click when the element has no button/link identity" do
    steps = [SpecAI::Step.new(action: :click, locator: ["css", ".card"],
                              element: { tag: "div", text: "Open", id: nil, name: nil, type: nil }),
             SpecAI::Step.new(action: :assert_title, expected: "x")]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include('find(".card").click')
  end

  it "maps remaining actions to idiomatic Capybara" do
    steps = [
      SpecAI::Step.new(action: :click, locator: %w[link_text Pricing],
                       element: { tag: "a", text: "Pricing", id: nil, name: nil, type: nil }),
      SpecAI::Step.new(action: :select_option, locator: %w[id country], value: "Denmark", select_by: :text,
                       element: { tag: "select", text: "", id: "country", name: "country", type: nil }),
      SpecAI::Step.new(action: :wait_for, locator: ["css", ".spinner"], condition: "gone", timeout: 10),
      SpecAI::Step.new(action: :assert_element, locator: %w[id cart], condition: "present"),
      SpecAI::Step.new(action: :assert_url, expected: "checkout"),
      SpecAI::Step.new(action: :assert_text, expected: "Done")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include('click_link "Pricing"')
    expect(out).to include('select "Denmark", from: "country"')
    expect(out).to include('expect(page).to have_no_css(".spinner", visible: :all)')
    expect(out).to include(%q{expect(page).to have_css("[id='cart']", visible: :all)})
    expect(out).to include('expect(page).to have_current_path(Regexp.new("checkout"), url: true)')
    expect(out).to include('expect(page).to have_content("Done")')
  end

  it "exports wait_for xpath as have_xpath when visible" do
    steps = [
      SpecAI::Step.new(action: :wait_for, locator: ["xpath", "//div[@id='modal']"], condition: "visible",
                       timeout: 10),
      SpecAI::Step.new(action: :assert_title, expected: "x")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include('expect(page).to have_xpath("//div[@id=\'modal\']")')
  end

  it "exports wait_for link_text as have_no_link when gone" do
    steps = [
      SpecAI::Step.new(action: :wait_for, locator: %w[link_text Pricing], condition: "gone", timeout: 10),
      SpecAI::Step.new(action: :assert_title, expected: "x")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include('expect(page).to have_no_link("Pricing", visible: :all)')
  end

  it "exports wait_for css present with visible: :all" do
    steps = [
      SpecAI::Step.new(action: :wait_for, locator: %w[css .cart], condition: "present", timeout: 10),
      SpecAI::Step.new(action: :assert_title, expected: "x")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include('expect(page).to have_css(".cart", visible: :all)')
  end

  it "exports assert_element xpath present with visible: :all" do
    steps = [
      SpecAI::Step.new(action: :assert_element, locator: ["xpath", "//div[@id='cart']"], condition: "present"),
      SpecAI::Step.new(action: :assert_title, expected: "x")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include('expect(page).to have_xpath("//div[@id=\'cart\']", visible: :all)')
  end

  it "exports assert_element link_text visible without visible: :all" do
    steps = [
      SpecAI::Step.new(action: :assert_element, locator: %w[link_text Pricing], condition: "visible"),
      SpecAI::Step.new(action: :assert_title, expected: "x")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include('expect(page).to have_link("Pricing")')
  end

  it "exports select-by-value by targeting the option node, not option text" do
    steps = [
      SpecAI::Step.new(action: :select_option, locator: %w[id country], value: "DK", select_by: :value,
                       element: { tag: "select", text: "", id: "country", name: "country", type: nil }),
      SpecAI::Step.new(action: :assert_title, expected: "x")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include(%q{find("[id='country']").find("option[value='DK']").select_option})
  end

  it "exports type without clear as send_keys to preserve append semantics" do
    steps = [
      SpecAI::Step.new(action: :type, locator: %w[id notes], value: " appended",
                       element: { tag: "textarea", text: "", id: "notes", name: "notes", type: nil }),
      SpecAI::Step.new(action: :assert_title, expected: "x")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include(%q{find("[id='notes']").send_keys(" appended")})
    expect(out).not_to include("fill_in")
  end

  it "scopes assert_text by link_text via find_link, not a bogus css selector" do
    steps = [
      SpecAI::Step.new(action: :assert_text, expected: "Pricing plans", scope: %w[link_text Pricing]),
      SpecAI::Step.new(action: :assert_title, expected: "x")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include('expect(find_link("Pricing")).to have_content("Pricing plans")')
  end

  it "escapes select-by-value so a hostile option value cannot break or inject Ruby" do
    steps = [
      SpecAI::Step.new(action: :select_option, locator: %w[id size], value: %q{x'); system("boom"); ('},
                       select_by: :value,
                       element: { tag: "select", text: "", id: "size", name: "size", type: nil }),
      SpecAI::Step.new(action: :assert_title, expected: "x")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect { RubyVM::InstructionSequence.compile(out) }.not_to raise_error
    expect(out).not_to include('system("boom")')
  end

  it "escapes id locators with CSS metacharacters into valid Ruby and CSS" do
    steps = [
      SpecAI::Step.new(action: :click, locator: ["id", "items[0][name]"],
                       element: { tag: "div", text: "", id: "items[0][name]", name: nil, type: nil }),
      SpecAI::Step.new(action: :assert_title, expected: "x")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect { RubyVM::InstructionSequence.compile(out) }.not_to raise_error
    expect(out).to include(%q{find("[id='items[0][name]']").click})
  end

  it "escapes an apostrophe in a name locator" do
    steps = [
      SpecAI::Step.new(action: :click, locator: ["name", "user's_field"],
                       element: { tag: "input", text: "", id: nil, name: "user's_field", type: "text" }),
      SpecAI::Step.new(action: :assert_title, expected: "x")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect { RubyVM::InstructionSequence.compile(out) }.not_to raise_error
    expect(out).to include(%q{find("[name='user\\\\'s_field']").click})
  end

  it "warns when a recording spans multiple hosts" do
    steps = [
      SpecAI::Step.new(action: :navigate, value: "https://a.example.com/one"),
      SpecAI::Step.new(action: :navigate, value: "https://b.example.com/two"),
      SpecAI::Step.new(action: :assert_title, expected: "x")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include("# WARNING: this recording spans multiple hosts (a.example.com, b.example.com)")
    expect(out).to include('visit "/one"')
    expect(out).to include('visit "/two"')
  end

  it "warns when a recording has multiple browser sessions" do
    steps = [
      SpecAI::Step.new(action: :start_browser, value: "chrome", headless: true),
      SpecAI::Step.new(action: :start_browser, value: "firefox", headless: false),
      SpecAI::Step.new(action: :assert_title, expected: "x")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include("# WARNING: this recording has 2 browser sessions")
  end

  it "keeps query and fragment in visited paths" do
    steps = [
      SpecAI::Step.new(action: :navigate, value: "https://example.com/app?tab=2#/checkout"),
      SpecAI::Step.new(action: :assert_title, expected: "x")
    ]
    out = described_class.render(steps: steps, description: "d")
    expect(out).to include('visit "/app?tab=2#/checkout"')
  end
end
