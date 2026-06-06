require "rails_helper"

RSpec.describe "Auth::OmniauthCallbacks", type: :request do
  describe "GET /auth/google_oauth2/callback" do
    context "when an existing user with the same email exists (B4-A)" do
      let!(:user) { create(:user, email: "u1@example.com") }

      it "logs in the user and links a new oauth_identity" do
        mock_oauth_response!(uid: "g-1", email: "u1@example.com")

        expect {
          get "/auth/google_oauth2/callback"
        }.to change { user.reload.oauth_identities.count }.by(1)

        expect(session[:user_id]).to eq(user.id)
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to be_present
      end
    end

    context "when no user exists but the email matches allowed_email_domain (B5-B)" do
      before { ApplicationSetting.instance.update!(allowed_email_domain: "example.com") }

      it "auto-creates a member user and logs them in" do
        mock_oauth_response!(uid: "g-2", email: "new@example.com")

        expect {
          get "/auth/google_oauth2/callback"
        }.to change(User, :count).by(1)

        new_user = User.find_by(email: "new@example.com")
        expect(new_user.role).to eq("member")
        expect(session[:user_id]).to eq(new_user.id)
        expect(response).to redirect_to(root_path)
      end
    end

    context "when the email is not allowed" do
      before { ApplicationSetting.instance.update!(allowed_email_domain: "example.com") }

      it "redirects back to login with an error and does not log in" do
        mock_oauth_response!(uid: "g-3", email: "stranger@other.com")

        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change(User, :count)

        expect(session[:user_id]).to be_nil
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "GET /auth/failure" do
    it "redirects to login with an error flash" do
      get "/auth/failure", params: { message: "invalid_credentials" }
      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to be_present
    end
  end
end
