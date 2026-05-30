require "rails_helper"

RSpec.describe "Health check", type: :system do
  it "returns 200 on /up" do
    visit "/up"
    expect(page.status_code).to eq(200)
  end
end
