# frozen_string_literal: true

RSpec.describe SpecAI::Tools::Snapshot do
  let(:session) { FakeSession.new }
  let(:app) { SpecAI::App.new(session: session, recorder: SpecAI::Recorder.new) }
  let(:ctx) { { app: app } }

  before { session.alive = true }

  it "lists interactive elements with suggested locators" do
    allow(session).to receive(:snapshot).and_return(
      [
        { "tag" => "button", "id" => "login-btn", "name" => nil, "type" => "submit",
          "text" => "Log in", "href" => nil },
        { "tag" => "input", "id" => nil, "name" => "email", "type" => "text",
          "text" => "", "href" => nil },
        { "tag" => "h1", "id" => nil, "name" => nil, "type" => nil,
          "text" => "Welcome", "href" => nil }
      ]
    )
    res = described_class.call(server_context: ctx)
    out = res.content.first[:text]
    expect(out).to include("Interactive elements (3):")
    expect(out).to include('- button "Log in" [locator: id=login-btn]')
    expect(out).to include('- input "" [locator: name=email]')
    expect(out).to include('- h1 "Welcome" [no unique locator - inspect with find_element or use css/xpath]')
    expect(app.recorder.steps.last.action).to eq(:snapshot)
  end

  it "reports an empty page" do
    allow(session).to receive(:snapshot).and_return([])
    res = described_class.call(server_context: ctx)
    expect(res.content.first[:text]).to include("Interactive elements (0):")
  end
end
