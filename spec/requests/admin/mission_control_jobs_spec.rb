require "rails_helper"

RSpec.describe "Admin::MissionControlJobs", type: :request do
  let(:admin) { create(:user, :admin, password: "password") }
  let(:member) { create(:user, :member, password: "password") }

  def login_as(user, password: "password")
    post session_path, params: { email: user.email, password: password }
  end

  describe "GET /jobs" do
    it "redirects unauthenticated users to login" do
      admin # User を 1 件以上作って setup ウィザードへの誘導を回避する
      get "/jobs"
      expect(response).to redirect_to("/session/new")
    end

    it "blocks non-admin members" do
      login_as(member)
      get "/jobs"
      expect(response).to redirect_to("/")
    end

    it "allows admin to access the Mission Control dashboard" do
      login_as(admin)
      get "/jobs"
      expect(response).to have_http_status(:ok)
    end
  end
end
