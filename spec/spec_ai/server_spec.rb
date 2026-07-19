# frozen_string_literal: true

require "open3"
require "json"

RSpec.describe SpecAI::Server do
  let(:expected_tools) do
    %w[
      start_browser navigate snapshot find_element click type select_option screenshot
      execute_script wait_for close_browser assert_text assert_title assert_element
      assert_url export_spec reset_recording
    ]
  end

  it "registers exactly the 17 designed tools" do
    expect(SpecAI::Tools::ALL.size).to eq(17)
  end

  it "builds an MCP server" do
    expect(described_class.build).to be_a(MCP::Server)
  end

  def parse_json_line(line)
    JSON.parse(line)
  rescue JSON::ParserError
    nil
  end

  it "answers tools/list over stdio with all 17 tools" do
    requests = [
      { jsonrpc: "2.0", id: 1, method: "initialize",
        params: { protocolVersion: "2025-06-18", capabilities: {},
                  clientInfo: { name: "spec", version: "0" } } },
      { jsonrpc: "2.0", method: "notifications/initialized" },
      { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }
    ].map(&:to_json).join("\n")

    stdout, _stderr, status = Open3.capture3("ruby", "exe/spec_ai", stdin_data: "#{requests}\n")
    expect(status.exitstatus).to eq(0).or be_nil
    tools_line = stdout.lines.filter_map { |l| parse_json_line(l) }.find { |m| m["id"] == 2 }
    expect(tools_line).not_to be_nil, "no tools/list response in: #{stdout.inspect}"
    names = tools_line.dig("result", "tools").map { |t| t["name"] }
    expect(names).to match_array(expected_tools)
  end
end
