require "rails_helper"

RSpec.describe "SSO (Google ログイン)", type: :system do
  let!(:user) { create(:user, email: "existing@example.com") }

  # ENV を直接読まず Rails.configuration.x.sso_enabled を直接トグル（finding D/T）。
  # test 環境のデフォルトは true なので after で必ず true に戻す。
  after { Rails.configuration.x.sso_enabled = true }

  context "when SSO is disabled" do
    before do
      Rails.configuration.x.sso_enabled = false
      visit new_session_path
    end

    it "does not show the Google login button" do
      expect(page).not_to have_button("Google でログイン")
    end
  end

  context "when SSO is enabled" do
    before do
      Rails.configuration.x.sso_enabled = true
    end

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
