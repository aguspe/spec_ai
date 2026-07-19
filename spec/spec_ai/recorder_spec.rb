# frozen_string_literal: true

RSpec.describe SpecAI::Recorder do
  subject(:recorder) { described_class.new }

  it "starts empty" do
    expect(recorder).to be_empty
  end

  it "records steps in order and returns copies" do
    recorder.record(action: :navigate, value: "https://example.com/login")
    recorder.record(action: :click, locator: %w[id login-btn],
                    element: { tag: "button", text: "Log in", id: "login-btn", name: nil, type: "submit" })
    steps = recorder.steps
    expect(steps.map(&:action)).to eq(%i[navigate click])
    steps.pop
    expect(recorder.steps.size).to eq(2)
  end

  it "reset clears all steps" do
    recorder.record(action: :navigate, value: "https://example.com")
    recorder.reset
    expect(recorder).to be_empty
  end

  it "detects assertions" do
    recorder.record(action: :click, locator: %w[id x])
    expect(recorder.assertions?).to be false
    recorder.record(action: :assert_text, expected: "Welcome")
    expect(recorder.assertions?).to be true
  end
end
