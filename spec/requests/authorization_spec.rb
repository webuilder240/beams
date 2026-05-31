require "rails_helper"

RSpec.describe "Authorization", type: :request do
  def login_as(user, password: "password")
    post session_path, params: { email: user.email, password: password }
  end

  describe "admin-only endpoints (/admin/users)" do
    context "when not logged in" do
      it "redirects to the login page" do
        create(:user) # 初回セットアップ誘導を回避（ユーザーが存在する状態）
        get admin_users_path
        expect(response).to redirect_to(new_session_path)
      end
    end

    context "as a member" do
      let(:member) { create(:user, :member, password: "password") }

      it "is redirected to root with an alert" do
        login_as(member)
        get admin_users_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "as an admin" do
      let(:admin) { create(:user, :admin, password: "password") }

      it "is allowed in" do
        login_as(admin)
        get admin_users_path
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
