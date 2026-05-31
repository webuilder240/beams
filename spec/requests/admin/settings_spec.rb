require "rails_helper"

RSpec.describe "Admin::Settings", type: :request do
  let(:admin) { create(:user, :admin, password: "password") }
  let(:member) { create(:user, :member, password: "password") }

  def login_as(user, password: "password")
    post session_path, params: { email: user.email, password: password }
  end

  describe "access control" do
    it "blocks members from the edit form" do
      login_as(member)
      get edit_admin_settings_path
      expect(response).to redirect_to(root_path)
    end

    it "blocks members from updating the rate" do
      login_as(member)
      patch admin_settings_path, params: { application_setting: { bigquery_yen_per_tb: 1 } }
      expect(response).to redirect_to(root_path)
      expect(ApplicationSetting.instance.bigquery_yen_per_tb).to eq(950.0)
    end
  end

  context "as an admin" do
    before { login_as(admin) }

    describe "GET /admin/settings/edit" do
      it "renders the form with the current rate" do
        get edit_admin_settings_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("950")
      end
    end

    describe "PATCH /admin/settings" do
      it "updates the rate" do
        patch admin_settings_path, params: { application_setting: { bigquery_yen_per_tb: 1200.5 } }
        expect(response).to redirect_to(edit_admin_settings_path)
        expect(ApplicationSetting.instance.bigquery_yen_per_tb).to eq(1200.5)
      end

      it "re-renders on invalid (negative) input" do
        patch admin_settings_path, params: { application_setting: { bigquery_yen_per_tb: -5 } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(ApplicationSetting.instance.bigquery_yen_per_tb).to eq(950.0)
      end
    end
  end
end
