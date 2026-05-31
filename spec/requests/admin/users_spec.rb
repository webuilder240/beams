require "rails_helper"

RSpec.describe "Admin::Users", type: :request do
  let(:admin) { create(:user, :admin, password: "password") }
  let(:member) { create(:user, :member, password: "password") }

  def login_as(user, password: "password")
    post session_path, params: { email: user.email, password: password }
  end

  describe "access control" do
    it "blocks members from the index" do
      login_as(member)
      get admin_users_path
      expect(response).to redirect_to(root_path)
    end

    it "blocks members from creating users" do
      login_as(member)
      expect {
        post admin_users_path, params: { user: { email: "x@example.com", password: "password", role: "member" } }
      }.not_to change(User, :count)
      expect(response).to redirect_to(root_path)
    end
  end

  context "as an admin" do
    before { login_as(admin) }

    describe "GET /admin/users" do
      it "lists users" do
        member
        get admin_users_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(member.email)
      end
    end

    describe "GET /admin/users/new" do
      it "renders the new form" do
        get new_admin_user_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /admin/users" do
      it "creates a user" do
        expect {
          post admin_users_path, params: {
            user: { email: "new@example.com", password: "password123", role: "admin" }
          }
        }.to change(User, :count).by(1)
        expect(response).to redirect_to(admin_users_path)
        created = User.find_by(email: "new@example.com")
        expect(created.role).to eq("admin")
        expect(created.authenticate("password123")).to be_truthy
      end

      it "re-renders on invalid input" do
        expect {
          post admin_users_path, params: { user: { email: "bad", password: "", role: "member" } }
        }.not_to change(User, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    describe "GET /admin/users/:id/edit" do
      it "renders the edit form" do
        get edit_admin_user_path(member)
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PATCH /admin/users/:id" do
      it "updates the role without requiring a password" do
        patch admin_user_path(member), params: { user: { role: "admin" } }
        expect(response).to redirect_to(admin_users_path)
        expect(member.reload.role).to eq("admin")
      end

      it "re-renders on invalid input" do
        patch admin_user_path(member), params: { user: { email: "" } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(member.reload.email).not_to eq("")
      end
    end

    describe "DELETE /admin/users/:id" do
      it "deletes the user" do
        target = create(:user, :member)
        expect {
          delete admin_user_path(target)
        }.to change(User, :count).by(-1)
        expect(response).to redirect_to(admin_users_path)
      end
    end

    describe "PATCH /admin/users/:id/reset_password" do
      it "sets a new password the target user can log in with" do
        patch reset_password_admin_user_path(member), params: { user: { password: "brandnew1" } }
        expect(response).to redirect_to(admin_users_path)
        expect(member.reload.authenticate("brandnew1")).to be_truthy
      end

      it "re-renders edit on blank password" do
        patch reset_password_admin_user_path(member), params: { user: { password: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
