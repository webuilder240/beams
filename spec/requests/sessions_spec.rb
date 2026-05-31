require "rails_helper"

RSpec.describe "Sessions", type: :request do
  describe "GET /session/new" do
    it "renders the login form" do
      get new_session_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("type=\"email\"")
      expect(response.body).to include("type=\"password\"")
    end
  end

  describe "POST /session" do
    let!(:user) { create(:user, email: "login@example.com", password: "secret123") }

    context "with valid credentials" do
      it "logs the user in and redirects" do
        post session_path, params: { email: "login@example.com", password: "secret123" }
        expect(session[:user_id]).to eq(user.id)
        expect(response).to redirect_to(root_path)
      end

      it "normalizes the submitted email" do
        post session_path, params: { email: "  LOGIN@example.COM ", password: "secret123" }
        expect(session[:user_id]).to eq(user.id)
      end
    end

    context "with invalid credentials" do
      it "re-renders the form with an error and no session" do
        post session_path, params: { email: "login@example.com", password: "wrong" }
        expect(session[:user_id]).to be_nil
        expect(response).to have_http_status(:unprocessable_content)
        expect(flash[:alert]).to be_present
      end

      it "does not log in an unknown email" do
        post session_path, params: { email: "nobody@example.com", password: "secret123" }
        expect(session[:user_id]).to be_nil
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE /session" do
    let!(:user) { create(:user, password: "secret123") }

    it "logs the user out" do
      post session_path, params: { email: user.email, password: "secret123" }
      expect(session[:user_id]).to eq(user.id)

      delete session_path
      expect(session[:user_id]).to be_nil
      expect(response).to redirect_to(new_session_path)
    end
  end
end
