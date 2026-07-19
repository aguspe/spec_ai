# frozen_string_literal: true

require "tmpdir"

RSpec.describe "codegen tools" do
  let(:session) { FakeSession.new }
  let(:recorder) { SpecAI::Recorder.new }
  let(:app) { SpecAI::App.new(session: session, recorder: recorder) }
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
    res = SpecAI::Tools::ExportSpec.call(description: "Login flow", server_context: ctx)
    expect(response_text(res)).to include('RSpec.describe "Login flow" do')
    expect(response_text(res)).to include('require "selenium-webdriver"')
  end

  it "exports capybara format on request" do
    res = SpecAI::Tools::ExportSpec.call(description: "Login flow", format: "capybara", server_context: ctx)
    expect(response_text(res)).to include("type: :system")
    expect(response_text(res)).to include('visit "/login"')
  end

  it "writes to a path when given" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "specs", "login_spec.rb")
      res = SpecAI::Tools::ExportSpec.call(description: "Login flow", path: path, server_context: ctx)
      expect(File.read(path)).to include('RSpec.describe "Login flow" do')
      expect(response_text(res)).to include("Spec written to #{path}")
    end
  end

  it "refuses to export an empty recording" do
    recorder.reset
    res = SpecAI::Tools::ExportSpec.call(description: "x", server_context: ctx)
    expect(response_text(res)).to eq("ERROR: Nothing recorded yet - drive the browser first, then export.")
  end

  it "reset_recording clears steps but not the session" do
    session.alive = true
    res = SpecAI::Tools::ResetRecording.call(server_context: ctx)
    expect(response_text(res)).to include("Recording cleared")
    expect(recorder).to be_empty
    expect(session).to be_alive
  end
end
