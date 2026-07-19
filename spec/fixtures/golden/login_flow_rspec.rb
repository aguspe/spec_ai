require "selenium-webdriver"
require "rspec"

RSpec.describe "Login flow" do
  before do
    options = Selenium::WebDriver::Options.chrome
    options.add_argument("--headless=new")
    @driver = Selenium::WebDriver.for :chrome, options: options
    @wait = Selenium::WebDriver::Wait.new(timeout: 10)
  end

  after { @driver.quit }

  it "replays the recorded session" do
    @driver.navigate.to "https://example.com/login"
    @driver.find_element(id: "email").send_keys "user@example.com"
    @driver.find_element(id: "password").send_keys ENV.fetch("SPEC_AI_PASSWORD")
    @driver.find_element(id: "login-btn").click
    @wait.until { @driver.find_element(css: ".welcome").displayed? }
    expect(@driver.find_element(css: ".welcome").text).to include("Welcome back")
  end
end
