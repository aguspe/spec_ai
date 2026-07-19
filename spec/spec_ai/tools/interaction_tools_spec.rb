# frozen_string_literal: true

RSpec.describe "interaction tools" do
  let(:session) { FakeSession.new }
  let(:app) { SpecAI::App.new(session: session, recorder: SpecAI::Recorder.new) }
  let(:ctx) { { app: app } }

  before { session.alive = true }

  def response_text(response)
    response.content.first[:text]
  end

  it "click records locator and element metadata" do
    res = SpecAI::Tools::Click.call(strategy: "id", value: "login-btn", server_context: ctx)
    expect(response_text(res)).to include("Clicked id=login-btn")
    step = app.recorder.steps.last
    expect(step.action).to eq(:click)
    expect(step.locator).to eq(%w[id login-btn])
    expect(step.element[:tag]).to eq("button")
  end

  it "type records plain values" do
    SpecAI::Tools::Type.call(strategy: "id", value: "email", text: "a@b.c", clear: true, server_context: ctx)
    step = app.recorder.steps.last
    expect(step.action).to eq(:type)
    expect(step.value).to eq("a@b.c")
    expect(step.clear).to be true
    expect(step.masked).to be_falsey
  end

  it "type masks password fields and never stores the value" do
    allow(session).to receive(:type).and_return({ tag: "input", type: "password", id: "password",
                                                  name: "password", text: "" })
    res = SpecAI::Tools::Type.call(strategy: "id", value: "password", text: "hunter2", server_context: ctx)
    step = app.recorder.steps.last
    expect(step.masked).to be true
    expect(step.value).to be_nil
    expect(response_text(res)).to include("password field - value masked in recording")
    expect(app.recorder.steps.map(&:value)).not_to include("hunter2")
  end

  it "select_option records the chosen option and select_by" do
    SpecAI::Tools::SelectOption.call(strategy: "id", value: "country", text: "Denmark", server_context: ctx)
    step = app.recorder.steps.last
    expect(step.action).to eq(:select_option)
    expect(step.value).to eq("Denmark")
    expect(step.select_by).to eq(:text)
  end

  it "wait_for records condition and timeout" do
    SpecAI::Tools::WaitFor.call(strategy: "css", value: ".welcome", condition: "visible",
                                timeout: 5, server_context: ctx)
    step = app.recorder.steps.last
    expect(step.condition).to eq("visible")
    expect(step.timeout).to eq(5)
  end

  it "wait_for timeout returns an error and records nothing" do
    session.raise_on_next = Selenium::WebDriver::Error::TimeoutError.new("timed out after 5 seconds")
    res = SpecAI::Tools::WaitFor.call(strategy: "css", value: ".gone", condition: "visible",
                                      timeout: 5, server_context: ctx)
    expect(response_text(res)).to start_with("ERROR: Timed out")
    expect(app.recorder).to be_empty
  end

  it "screenshot returns an image content block" do
    res = SpecAI::Tools::Screenshot.call(server_context: ctx)
    block = res.content.first
    expect(block[:type]).to eq("image")
    expect(block[:mimeType]).to eq("image/png")
    expect(block[:data]).to eq("aGVsbG8=")
  end

  it "execute_script records the js and flags it as manual" do
    res = SpecAI::Tools::ExecuteScript.call(script: "return 1", server_context: ctx)
    expect(response_text(res)).to include("exported only as a MANUAL comment")
    expect(app.recorder.steps.last.js).to eq("return 1")
  end

  it "find_element reports the element without changing the page" do
    res = SpecAI::Tools::FindElement.call(strategy: "id", value: "login-btn", server_context: ctx)
    expect(response_text(res)).to include("button")
    expect(app.recorder.steps.last.action).to eq(:find_element)
  end

  it "find_element surfaces ElementNotFoundError message with suggestions" do
    session.raise_on_next = SpecAI::ElementNotFoundError.new(%w[id missing], ['button "Log in" [id=login-btn]'])
    res = SpecAI::Tools::FindElement.call(strategy: "id", value: "missing", server_context: ctx)
    expect(response_text(res)).to include("ERROR: Element not found: id \"missing\". Did you mean")
  end
end
