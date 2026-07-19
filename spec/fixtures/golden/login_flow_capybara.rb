require "rails_helper"

RSpec.describe "Login flow", type: :system do
  it "replays the recorded session" do
    visit "/login"
    fill_in "email", with: "user@example.com"
    fill_in "password", with: ENV.fetch("SPEC_AI_PASSWORD")
    click_button "Log in"
    expect(page).to have_css(".welcome")
    expect(find(".welcome")).to have_content("Welcome back")
  end
end
