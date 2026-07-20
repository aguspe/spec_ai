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
    expect(meta).to eq(tag: "button", text: "Log in", id: "login-btn", name: nil, type: "submit")
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
