# frozen_string_literal: true

RSpec.describe "session tools" do
  let(:session) { FakeSession.new }
  let(:app) { SpecAI::App.new(session: session, recorder: SpecAI::Recorder.new) }
  let(:ctx) { { app: app } }

  def response_text(response)
    response.content.first[:text]
  end

  it "start_browser starts the session and records the step" do
    res = SpecAI::Tools::StartBrowser.call(browser: "chrome", headless: true, server_context: ctx)
    expect(response_text(res)).to include("Started chrome")
    step = app.recorder.steps.last
    expect(step.action).to eq(:start_browser)
    expect(step.value).to eq("chrome")
    expect(step.headless).to be true
  end

  it "navigate records and reports title and url" do
    session.alive = true
    res = SpecAI::Tools::Navigate.call(url: "https://example.com/login", server_context: ctx)
    expect(response_text(res)).to include("Example Login").and include("https://example.com/login")
    expect(app.recorder.steps.last.action).to eq(:navigate)
  end

  it "navigate without a session returns the no-session error and records nothing" do
    session.raise_on_next = SpecAI::SessionNotStartedError
    res = SpecAI::Tools::Navigate.call(url: "https://x.test", server_context: ctx)
    expect(response_text(res)).to eq("ERROR: No browser session. Call start_browser first.")
    expect(app.recorder).to be_empty
  end

  it "close_browser quits and preserves the recording" do
    session.alive = true
    app.recorder.record(action: :navigate, value: "https://x.test")
    res = SpecAI::Tools::CloseBrowser.call(server_context: ctx)
    expect(response_text(res)).to include("Recording preserved")
    expect(app.recorder.steps.map(&:action)).to eq(%i[navigate close_browser])
  end
end
