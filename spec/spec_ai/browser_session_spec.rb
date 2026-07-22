# frozen_string_literal: true

RSpec.describe SpecAI::BrowserSession do
  let(:fake_element) do
    instance_double(Selenium::WebDriver::Element).tap do |el|
      allow(el).to receive_messages(tag_name: "button", text: "Log in", click: nil)
      allow(el).to receive(:attribute).with("id").and_return("login-btn")
      allow(el).to receive(:attribute).with("name").and_return(nil)
      allow(el).to receive(:attribute).with("type").and_return("submit")
    end
  end

  let(:fake_driver) do
    double("driver").tap do |d| # rubocop:disable RSpec/VerifiedDoubles
      allow(d).to receive_messages(quit: nil, current_url: "https://x.test/", title: "X")
      allow(d).to receive(:find_element).with({ id: "login-btn" }).and_return(fake_element)
      allow(d).to receive(:execute_script).and_return(1)
    end
  end

  let(:session) { described_class.new(driver_factory: ->(_browser, _headless) { fake_driver }) }

  it "raises SessionNotStartedError before start" do
    expect { session.navigate("https://x.test") }.to raise_error(SpecAI::SessionNotStartedError)
  end

  it "starts and reports alive" do
    session.start(browser: "chrome")
    expect(session).to be_alive
    expect(session.browser_name).to eq("chrome")
  end

  it "click returns element metadata captured before the click" do
    session.start(browser: "chrome")
    meta = session.click(%w[id login-btn])
    expect(meta).to include(tag: "button", text: "Log in", id: "login-btn", name: nil, type: "submit")
  end

  it "marks a click ambiguous when the button text matches more than one element" do
    session.start(browser: "chrome")
    allow(fake_driver).to receive(:execute_script).with(anything, "button", "Log in").and_return(2)
    expect(session.click(%w[id login-btn])[:unique]).to be(false)
  end

  it "marks a click unique when the button text matches exactly one element" do
    session.start(browser: "chrome")
    allow(fake_driver).to receive(:execute_script).with(anything, "button", "Log in").and_return(1)
    expect(session.click(%w[id login-btn])[:unique]).to be(true)
  end

  it "wraps NoSuchElementError into ElementNotFoundError with suggestions" do
    session.start(browser: "chrome")
    allow(fake_driver).to receive(:find_element).with({ id: "missing" })
                                                .and_raise(Selenium::WebDriver::Error::NoSuchElementError)
    session.instance_variable_set(:@last_snapshot,
                                  [{ "tag" => "button", "id" => "login-btn", "name" => nil, "text" => "Log in" }])
    session.instance_variable_set(:@last_snapshot_url, "https://x.test/")
    expect { session.find(%w[id missing]) }.to raise_error(SpecAI::ElementNotFoundError, /Did you mean/)
  end

  it "drops suggestions once the page has changed since the snapshot" do
    session.start(browser: "chrome")
    allow(fake_driver).to receive(:find_element).with({ id: "missing" })
                                                .and_raise(Selenium::WebDriver::Error::NoSuchElementError)
    session.instance_variable_set(:@last_snapshot,
                                  [{ "tag" => "button", "id" => "login-btn", "name" => nil, "text" => "Log in" }])
    session.instance_variable_set(:@last_snapshot_url, "https://x.test/previous-page")
    expect { session.find(%w[id missing]) }.to raise_error(SpecAI::ElementNotFoundError) do |error|
      expect(error.message).not_to include("Did you mean")
    end
  end

  it "swallows connection errors from quit on a crashed driver" do
    session.start(browser: "chrome")
    allow(fake_driver).to receive(:quit).and_raise(Errno::ECONNREFUSED)
    expect { session.quit }.not_to raise_error
    expect(session).not_to be_alive
  end

  it "quits the old driver when restarting after the session died" do
    session.start(browser: "chrome")
    allow(fake_driver).to receive(:current_url).and_raise(Selenium::WebDriver::Error::InvalidSessionIdError)
    expect { session.current_url }.to raise_error(SpecAI::SessionDeadError)
    session.start(browser: "chrome")
    expect(fake_driver).to have_received(:quit)
    expect(session).to be_alive
  end

  it "marks session dead on InvalidSessionIdError and raises SessionDeadError afterwards" do
    session.start(browser: "chrome")
    allow(fake_driver).to receive(:current_url).and_raise(Selenium::WebDriver::Error::InvalidSessionIdError)
    expect { session.current_url }.to raise_error(SpecAI::SessionDeadError)
    expect { session.title }.to raise_error(SpecAI::SessionDeadError)
    expect(session).not_to be_alive
  end

  it "marks session dead on a raw transport error instead of leaking it" do
    session.start(browser: "chrome")
    allow(fake_driver).to receive(:current_url).and_raise(Errno::EPIPE)
    expect { session.current_url }.to raise_error(SpecAI::SessionDeadError)
    expect(session).not_to be_alive
  end

  it "rejects a browser outside the supported list before dispatching to Options" do
    bad = described_class.new
    expect { bad.start(browser: "netscape") }.to raise_error(ArgumentError, /unsupported browser/)
  end

  it "leaves snapshot state consistent when the url read fails" do
    session.start(browser: "chrome")
    allow(fake_driver).to receive(:execute_script).and_return([{ "id" => "x" }])
    allow(fake_driver).to receive(:current_url).and_raise(Selenium::WebDriver::Error::WebDriverError)
    expect { session.snapshot }.to raise_error(Selenium::WebDriver::Error::WebDriverError)
    expect(session.last_snapshot).to eq([])
  end

  it "raises OptionNotFoundError listing available options when a select value is missing" do
    session.start(browser: "chrome")
    select = instance_double(Selenium::WebDriver::Support::Select)
    option = instance_double(Selenium::WebDriver::Element, text: "Denmark")
    allow(option).to receive(:attribute).with("value").and_return("DK")
    allow(select).to receive(:options).and_return([option])
    allow(select).to receive(:select_by).with(:value, "XX")
                                        .and_raise(Selenium::WebDriver::Error::NoSuchElementError)
    allow(Selenium::WebDriver::Support::Select).to receive(:new).and_return(select)
    allow(fake_driver).to receive(:find_element).with({ id: "country" }).and_return(fake_element)

    expect { session.select_option(%w[id country], value: "XX") }
      .to raise_error(SpecAI::OptionNotFoundError, /No option with value "XX".*Available: "DK"/m)
  end

  it "rejects a wait_for with an unknown condition instead of burning the timeout" do
    session.start(browser: "chrome")
    expect { session.wait_for(%w[css .x], condition: "invisible") }
      .to raise_error(ArgumentError, /unknown wait condition/)
  end

  it "rejects a select_option with neither text nor value" do
    session.start(browser: "chrome")
    expect { session.select_option(%w[id country]) }.to raise_error(ArgumentError, /provide text or value/)
  end

  it "treats an empty-string text/value as absent rather than selecting by empty" do
    session.start(browser: "chrome")
    expect { session.select_option(%w[id country], text: "", value: "") }
      .to raise_error(ArgumentError, /provide text or value/)
  end

  it "identifies password fields from metadata" do
    expect(session.password_field?(type: "password")).to be true
    expect(session.password_field?(type: "text")).to be false
  end

  it "marks session dead when metadata capture raises InvalidSessionIdError" do
    session.start(browser: "chrome")
    allow(fake_element).to receive(:tag_name).and_raise(Selenium::WebDriver::Error::InvalidSessionIdError)
    expect { session.click(%w[id login-btn]) }.to raise_error(SpecAI::SessionDeadError)
    expect(session).not_to be_alive
  end
end
