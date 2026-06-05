require "rails_helper"

RSpec.describe "SSO (Google ログイン)", type: :system do
  let!(:user) { create(:user, email: "existing@example.com") }

  context "when GOOGLE_OAUTH_CLIENT_ID is not set" do
    before do
      ENV.delete("GOOGLE_OAUTH_CLIENT_ID")
      visit new_session_path
    end

    it "does not show the Google login button" do
      expect(page).not_to have_button("Google でログイン")
    end
  end

  context "when GOOGLE_OAUTH_CLIENT_ID is set" do
    before do
      ENV["GOOGLE_OAUTH_CLIENT_ID"] = "dummy-id"
    end

    after { ENV.delete("GOOGLE_OAUTH_CLIENT_ID") }

    it "shows the Google login button on the login page (B7-B)" do
      visit new_session_path
      expect(page).to have_button("Google でログイン")
    end

    it "logs in via OmniAuth mock for an existing email" do
      mock_oauth_response!(uid: "g-system-1", email: "existing@example.com")

      visit "/auth/google_oauth2/callback"

      expect(page).to have_current_path(root_path)
      expect(page).to have_content("existing@example.com")
      expect(user.reload.oauth_identities.count).to eq(1)
    end
  end
end
