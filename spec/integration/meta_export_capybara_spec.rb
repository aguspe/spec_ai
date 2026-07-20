# frozen_string_literal: true

require "tmpdir"
require "open3"
require "webrick"

# Enforces the same "generated specs run green on first try" contract as
# meta_export_spec.rb, but for the Capybara/system-spec export format.
#
# The exported spec uses `require "rails_helper"` and `type: :system` with
# relative `visit` paths. To run it without a Rails app we serve the login
# fixture over HTTP and write a rails_helper shim that points Capybara at that
# server (run_server: false), so `visit "/login"` resolves correctly.
RSpec.describe "exported Capybara spec runs green", :browser do
  let(:fixture) { File.expand_path("../fixtures/site/login.html", __dir__) }

  def call(tool, app, **args)
    tool.call(**args, server_context: { app: app })
  end

  def start_fixture_server
    server = WEBrick::HTTPServer.new(Port: 0, BindAddress: "127.0.0.1",
                                     Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
    html = File.read(fixture)
    server.mount_proc("/login") do |_req, res|
      res.content_type = "text/html"
      res.body = html
    end
    port = server.listeners.first.addr[1]
    thread = Thread.new { server.start }
    [server, thread, port]
  end

  def rails_helper_shim
    <<~RUBY
      require "capybara/rspec"
      require "selenium-webdriver"

      Capybara.register_driver(:spec_ai_headless_chrome) do |app|
        options = Selenium::WebDriver::Options.chrome
        options.add_argument("--headless=new")
        options.add_argument("--no-sandbox")
        options.add_argument("--disable-dev-shm-usage")
        Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
      end

      Capybara.default_driver = :spec_ai_headless_chrome
      Capybara.app_host = ENV.fetch("CAPYBARA_APP_HOST")
      Capybara.run_server = false

      RSpec.configure do |config|
        config.include Capybara::DSL, type: :system
        config.include Capybara::RSpecMatchers, type: :system
        config.after { Capybara.reset_sessions! }
      end
    RUBY
  end

  it "drives the tools, exports Capybara format, and the generated system spec passes" do
    server, thread, port = start_fixture_server
    host = "http://127.0.0.1:#{port}"
    app = SpecAI::App.new

    call(SpecAI::Tools::StartBrowser, app, browser: "chrome", headless: true)
    call(SpecAI::Tools::Navigate, app, url: "#{host}/login")
    call(SpecAI::Tools::Type, app, strategy: "id", value: "email", text: "user@example.com")
    call(SpecAI::Tools::Type, app, strategy: "id", value: "password", text: "secret123")
    call(SpecAI::Tools::Click, app, strategy: "id", value: "login-btn")
    call(SpecAI::Tools::WaitFor, app, strategy: "css", value: ".welcome", condition: "visible", timeout: 5)
    call(SpecAI::Tools::AssertText, app, text: "Welcome back", scope_strategy: "css", scope_value: ".welcome")
    call(SpecAI::Tools::CloseBrowser, app)

    Dir.mktmpdir do |dir|
      spec_path = File.join(dir, "login_flow_system_spec.rb")
      call(SpecAI::Tools::ExportSpec, app, description: "Login flow", format: "capybara", path: spec_path)
      source = File.read(spec_path)
      expect(source).to include("type: :system")
      expect(source).to include('fill_in "email"')
      expect(source).to include('ENV.fetch("SPEC_AI_PASSWORD")')
      expect(source).not_to include("secret123")

      File.write(File.join(dir, "rails_helper.rb"), rails_helper_shim)
      out, status = Open3.capture2e(
        { "CAPYBARA_APP_HOST" => host, "SPEC_AI_PASSWORD" => "secret123" },
        "bundle", "exec", "rspec", "-I", dir, spec_path
      )
      expect(status).to be_success, "generated Capybara spec failed:\n#{out}"
    end
  ensure
    server&.shutdown
    thread&.join
  end
end
