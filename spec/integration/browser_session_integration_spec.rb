# frozen_string_literal: true

RSpec.describe SpecAI::BrowserSession, :browser do
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
      .to raise_error(SpecAI::ElementNotFoundError, /Did you mean/)
  end
end
